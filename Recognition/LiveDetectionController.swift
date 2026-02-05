import AVFoundation
import Foundation
import QuartzCore
import Vision
import UIKit
import ImageIO

final class LiveDetectionController: ObservableObject {
    @Published private(set) var detections: [CoinDetector.DetectedCoin] = []
    @Published private(set) var results: [CoinResult] = []
    @Published private(set) var statusText: String = "实时检测中…"

    private let processingQueue = DispatchQueue(label: "coin.live.detection.queue")
    private let minInterval: CFTimeInterval
    private var lastInferenceTime: CFTimeInterval = 0
    private var isProcessing = false

    private var frontTemplates: [VNFeaturePrintObservation] = []
    private var backTemplates: [VNFeaturePrintObservation] = []
    private var calibration = ConfidenceCalculator.Calibration.default
    private var frontDescriptors: [[Float]] = []
    private var backDescriptors: [[Float]] = []
    private var descriptorCalibration = FeatureMatchService.DescriptorCalibration.default
    private var smoother = CoinResultSmoother(windowSize: 8, minimumSamples: 4)
    private let ciContext = CIContext()
    private var isEnabled = true
    private var invertSides = false
    private var previewSize: CGSize = .zero
    private let presenceCalibration = ImageProcessor.CoinPresenceCalibration.default

    init(minInterval: CFTimeInterval = 0.15) {
        self.minInterval = minInterval
    }

    func updateProfile(_ profile: CoinProfile?) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            guard let profile = profile,
                  let frontData = TemplateManager.deserializeTemplateData(profile.frontTemplates),
                  let backData = TemplateManager.deserializeTemplateData(profile.backTemplates) else {
                self.frontTemplates = []
                self.backTemplates = []
                self.calibration = .default
                self.frontDescriptors = []
                self.backDescriptors = []
                self.descriptorCalibration = .default
                return
            }

            self.frontTemplates = frontData.getObservations()
            self.backTemplates = backData.getObservations()
            self.calibration = ConfidenceCalculator.calibrate(
                frontTemplates: self.frontTemplates,
                backTemplates: self.backTemplates
            )
            self.frontDescriptors = frontData.getDescriptors()
            self.backDescriptors = backData.getDescriptors()
            self.descriptorCalibration = FeatureMatchService.calibrateDescriptors(
                frontDescriptors: self.frontDescriptors,
                backDescriptors: self.backDescriptors
            )
        }
    }

    func setEnabled(_ enabled: Bool) {
        processingQueue.async { [weak self] in
            self?.isEnabled = enabled
        }
    }

    func setInvertSides(_ invert: Bool) {
        processingQueue.async { [weak self] in
            self?.invertSides = invert
        }
    }

    func setPreviewSize(_ size: CGSize) {
        processingQueue.async { [weak self] in
            self?.previewSize = size
        }
    }

    func handleFrame(_ pixelBuffer: CVPixelBuffer) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isEnabled else { return }
            let now = CACurrentMediaTime()
            guard now - self.lastInferenceTime >= self.minInterval else { return }
            guard !self.isProcessing else { return }

            self.isProcessing = true
            self.lastInferenceTime = now

            let frontTemplates = self.frontTemplates
            let backTemplates = self.backTemplates
            let calibration = self.calibration
            let frontDescriptors = self.frontDescriptors
            let backDescriptors = self.backDescriptors
            let descriptorCalibration = self.descriptorCalibration
            let hasTemplates = (!frontDescriptors.isEmpty && !backDescriptors.isEmpty)
                || (!frontTemplates.isEmpty && !backTemplates.isEmpty)

            Task.detached { [weak self] in
                guard let self = self else { return }
                defer {
                    self.processingQueue.async {
                        self.isProcessing = false
                    }
                }

                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                let orientation: CGImagePropertyOrientation = width >= height ? .right : .up

                guard let frameImage = ImageProcessor.imageFromPixelBuffer(
                    pixelBuffer,
                    orientation: orientation,
                    context: self.ciContext
                ) else {
                    return
                }

                let normalized = ImageProcessor.normalizeOrientation(frameImage)
                let detections = ROICropper.slotDetections(for: normalized, in: self.previewSize)
                let validDetections = detections.filter { detection in
                    let presenceScales: [CGFloat] = [1.0, 0.75]
                    var isPresent = false
                    var lastMetrics: ImageProcessor.CoinPresenceMetrics?

                    for scale in presenceScales {
                        let candidate = scale >= 0.999 ? detection.image : ImageProcessor.centerCrop(detection.image, scale: scale)
                        guard let metrics = ImageProcessor.coinPresenceMetrics(
                            for: candidate,
                            calibration: self.presenceCalibration
                        ) else {
                            continue
                        }
                        lastMetrics = metrics
                        if metrics.isPresent {
                            isPresent = true
                            break
                        }
                    }
                    #if DEBUG
                    if !isPresent, let metrics = lastMetrics {
                        print(String(format: "Presence: pos=%d energy=%.3f ring=%.3f", detection.position, metrics.energyMean, metrics.ringRatio))
                    }
                    #endif
                    return isPresent
                }
                let validCount = validDetections.count

                var results: [CoinResult] = []
                if validCount == 6, hasTemplates {
                    let roiCandidates: [(Int, [UIImage])] = validDetections.map { detection in
                        let zoomScales: [CGFloat] = [1.0, 0.82, 0.68]
                        var candidates = ImageProcessor.zoomedVariants(for: detection.image, scales: zoomScales)
                        if let masked = detection.maskedImage {
                            candidates.append(contentsOf: ImageProcessor.zoomedVariants(for: masked, scales: zoomScales))
                        }
                        return (detection.position, candidates)
                    }

                    results = await FeatureMatchService.matchAllCoinCandidates(
                        roiCandidates: roiCandidates,
                        frontTemplates: frontTemplates,
                        backTemplates: backTemplates,
                        calibration: calibration,
                        frontDescriptors: frontDescriptors,
                        backDescriptors: backDescriptors,
                        descriptorCalibration: descriptorCalibration
                    )
                    results = self.smoother.add(results: results)
                    if self.invertSides {
                        results = CoinResultTransformer.invertSides(results)
                    }
                } else {
                    self.smoother.reset()
                }

                let status = self.buildStatus(
                    validCount: validCount,
                    results: results,
                    hasTemplates: hasTemplates
                )

                DispatchQueue.main.async {
                    self.detections = validDetections
                    self.results = results
                    self.statusText = status
                }
            }
        }
    }

    func reset() {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            self.lastInferenceTime = 0
            self.isProcessing = false
            self.isEnabled = true
            self.smoother.reset()
        }

        DispatchQueue.main.async {
            self.detections = []
            self.results = []
            self.statusText = "实时检测中…"
        }
    }

    private func buildStatus(
        validCount: Int,
        results: [CoinResult],
        hasTemplates: Bool
    ) -> String {
        guard hasTemplates else {
            return "请先设置铜钱模板"
        }

        guard validCount > 0 else {
            return "未检测到铜钱"
        }

        if validCount < 6 {
            return "检测到\(validCount)枚，继续调整"
        }

        guard !results.isEmpty else {
            return "检测到6枚，匹配中…"
        }

        if results.contains(where: { $0.side == .uncertain || $0.side == .invalid }) {
            return "部分不确定，请调整光线或角度"
        }

        return "已识别6枚，正在展示结果"
    }
}
