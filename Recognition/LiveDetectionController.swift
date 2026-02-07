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
    @Published private(set) var shouldSuggestTorch: Bool = false

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
    private let qualityCalibration = ImageProcessor.CoinQualityCalibration.default
    private let stableFramesRequired = 6
    private var stableFrameCount = 0
    private let smootherResetMissLimit = 10
    private var qualityMissCount = 0
    private let lowLightFramesRequired = 8
    private var lowLightFrameCount = 0

    private struct SlotEvaluation {
        let detection: CoinDetector.DetectedCoin
        let isPresent: Bool
        let isQualityPass: Bool
        let isStrictQualityPass: Bool
        let energyMean: Float
        let qualityScore: Float
    }

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
                self.stableFrameCount = 0
                self.qualityMissCount = 0
                self.lowLightFrameCount = 0
                self.smoother.reset()
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
            self.stableFrameCount = 0
            self.qualityMissCount = 0
            self.lowLightFrameCount = 0
            self.smoother.reset()
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
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let orientation: CGImagePropertyOrientation = width >= height ? .right : .up
            guard let frameImage = ImageProcessor.imageFromPixelBuffer(
                pixelBuffer,
                orientation: orientation,
                context: self.ciContext
            ) else {
                self.isProcessing = false
                return
            }
            let normalized = ImageProcessor.normalizeOrientation(frameImage)

            Task.detached { [weak self] in
                guard let self = self else { return }
                defer {
                    self.processingQueue.async {
                        self.isProcessing = false
                    }
                }

                let detections = ROICropper.slotDetections(for: normalized, in: self.previewSize)
                let evaluations = detections.map { detection in
                    self.evaluateSlot(detection)
                }

                let presentDetections = evaluations
                    .filter { $0.isPresent }
                    .map(\.detection)
                let qualityDetections = evaluations
                    .filter { $0.isQualityPass }
                    .map(\.detection)
                let strictQualityCount = evaluations
                    .filter { $0.isStrictQualityPass }
                    .map(\.detection.position)
                    .reduce(into: Set<Int>()) { $0.insert($1) }
                    .count

                let presentCount = Set(presentDetections.map(\.position)).count
                let qualityCount = Set(qualityDetections.map(\.position)).count
                let qualityReady = qualityCount == 6 && strictQualityCount >= 4
                let lowLightSuggested = self.nextLowLightSuggestion(
                    evaluations: evaluations,
                    presentCount: presentCount,
                    qualityCount: qualityCount
                )

                self.stableFrameCount = Self.nextStableFrameCount(
                    current: self.stableFrameCount,
                    qualityReady: qualityReady,
                    required: self.stableFramesRequired
                )
                if qualityReady {
                    self.qualityMissCount = 0
                } else {
                    self.qualityMissCount = min(self.qualityMissCount + 1, self.smootherResetMissLimit)
                }
                let stableReady = self.stableFrameCount >= self.stableFramesRequired

                var results: [CoinResult] = []
                if stableReady, qualityReady, hasTemplates {
                    let lockedDetections = qualityDetections.sorted { $0.position < $1.position }
                    let roiCandidates: [(Int, [UIImage])] = lockedDetections.map { detection in
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
                    if self.qualityMissCount >= self.smootherResetMissLimit {
                        self.smoother.reset()
                    }
                }

                let status = self.buildStatus(
                    presentCount: presentCount,
                    qualityCount: qualityCount,
                    strictQualityCount: strictQualityCount,
                    stableFrameCount: self.stableFrameCount,
                    results: results,
                    hasTemplates: hasTemplates,
                    lowLightSuggested: lowLightSuggested
                )

                DispatchQueue.main.async {
                    self.detections = qualityDetections
                    self.results = results
                    self.statusText = status
                    self.shouldSuggestTorch = lowLightSuggested
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
            self.stableFrameCount = 0
            self.qualityMissCount = 0
            self.lowLightFrameCount = 0
            self.smoother.reset()
        }

        DispatchQueue.main.async {
            self.detections = []
            self.results = []
            self.statusText = "实时检测中…"
            self.shouldSuggestTorch = false
        }
    }

    private func buildStatus(
        presentCount: Int,
        qualityCount: Int,
        strictQualityCount: Int,
        stableFrameCount: Int,
        results: [CoinResult],
        hasTemplates: Bool,
        lowLightSuggested: Bool
    ) -> String {
        guard hasTemplates else {
            return "请先设置铜钱模板"
        }

        guard presentCount > 0 else {
            return "未检测到铜钱"
        }

        if presentCount < 6 {
            return "检测到\(presentCount)枚，继续调整"
        }

        if qualityCount < 6 {
            if lowLightSuggested {
                return "检测到6枚，光线偏暗，可尝试打开闪光灯"
            }
            return "检测到6枚，画面质量不足，请微调角度/光线"
        }

        if strictQualityCount < 4 {
            return "检测到6枚，定位偏移较大，请对齐中线后重试"
        }

        if stableFrameCount < stableFramesRequired {
            return "检测到6枚，稳定中 \(stableFrameCount)/\(stableFramesRequired)"
        }

        guard !results.isEmpty else {
            return "检测到6枚，匹配中…"
        }

        if !ResultReliabilityEvaluator.isReliable(results) {
            return "阴阳匹配稳定性不足，请微调角度/光线"
        }

        if results.contains(where: { $0.side == .uncertain || $0.side == .invalid }) {
            return "部分不确定，请调整光线或角度"
        }

        return "已识别6枚，正在展示结果"
    }

    private func nextLowLightSuggestion(
        evaluations: [SlotEvaluation],
        presentCount: Int,
        qualityCount: Int
    ) -> Bool {
        guard !evaluations.isEmpty else {
            lowLightFrameCount = 0
            return false
        }
        let avgEnergy = evaluations.reduce(0) { $0 + $1.energyMean } / Float(evaluations.count)
        let avgQuality = evaluations.reduce(0) { $0 + $1.qualityScore } / Float(evaluations.count)
        let lowLightFrame = presentCount >= 4
            && qualityCount < 6
            && avgEnergy < 0.11
            && avgQuality < 0.60

        if lowLightFrame {
            lowLightFrameCount = min(lowLightFrameCount + 1, lowLightFramesRequired)
        } else {
            lowLightFrameCount = max(lowLightFrameCount - 1, 0)
        }
        return lowLightFrameCount >= lowLightFramesRequired
    }

    private func evaluateSlot(_ detection: CoinDetector.DetectedCoin) -> SlotEvaluation {
        let presenceScales: [CGFloat] = [1.0]
        var isPresent = false
        var isQualityPass = false
        var isStrictQualityPass = false
        var bestMetrics: ImageProcessor.CoinPresenceMetrics?
        var bestQualityScore = -Float.greatestFiniteMagnitude

        for scale in presenceScales {
            let candidate = scale >= 0.999
                ? detection.image
                : ImageProcessor.centerCrop(detection.image, scale: scale)
            guard let metrics = ImageProcessor.coinPresenceMetrics(
                for: candidate,
                calibration: presenceCalibration
            ) else {
                continue
            }
            if metrics.qualityScore > bestQualityScore {
                bestQualityScore = metrics.qualityScore
                bestMetrics = metrics
            }
            if metrics.isPresent {
                isPresent = true
            }
            if ImageProcessor.isCoinHighQualityForSlot(
                position: detection.position,
                energyMean: metrics.energyMean,
                ringRatio: metrics.ringRatio,
                centroidOffset: metrics.centroidOffset,
                calibration: qualityCalibration
            ) {
                isQualityPass = true
            }
            if ImageProcessor.isCoinHighQuality(
                energyMean: metrics.energyMean,
                ringRatio: metrics.ringRatio,
                centroidOffset: metrics.centroidOffset,
                calibration: qualityCalibration
            ) {
                isStrictQualityPass = true
            }
        }

        #if DEBUG
        if let metrics = bestMetrics, (!isPresent || !isQualityPass) {
            let label = isPresent ? "QualityReject" : "Presence"
            print(
                String(
                    format: "%@: pos=%d energy=%.3f ring=%.3f offset=%.3f quality=%.3f",
                    label,
                    detection.position,
                    metrics.energyMean,
                    metrics.ringRatio,
                    metrics.centroidOffset,
                    metrics.qualityScore
                )
            )
        }
        #endif

        return SlotEvaluation(
            detection: detection,
            isPresent: isPresent,
            isQualityPass: isQualityPass,
            isStrictQualityPass: isStrictQualityPass,
            energyMean: bestMetrics?.energyMean ?? 0,
            qualityScore: bestMetrics?.qualityScore ?? 0
        )
    }

    static func nextStableFrameCount(
        current: Int,
        qualityReady: Bool,
        required: Int
    ) -> Int {
        let clampedRequired = max(required, 1)
        guard qualityReady else { return 0 }
        return min(current + 1, clampedRequired)
    }
}
