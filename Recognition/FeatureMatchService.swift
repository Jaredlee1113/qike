import Foundation
import Vision
import UIKit

class FeatureMatchService {
    struct DescriptorCalibration {
        let minGap: Float
        let minScore: Float

        static let `default` = DescriptorCalibration(minGap: 0.05, minScore: 0.55)
    }

    static func matchCoin(
        image: UIImage,
        frontTemplates: [VNFeaturePrintObservation],
        backTemplates: [VNFeaturePrintObservation],
        calibration: ConfidenceCalculator.Calibration = .default
    ) async -> (side: CoinSide, confidence: Double) {
        let processed = ImageProcessor.prepareCoinForMatching(image)
        let variants = [
            processed,
            ImageProcessor.applyColorControls(processed, contrast: 1.25, brightness: 0.04),
            ImageProcessor.applyColorControls(processed, contrast: 0.9, brightness: -0.04)
        ]

        var bestResult: (CoinSide, Double) = (.invalid, 0.0)
        var bestRank = 2

        for variant in variants {
            guard let featurePrint = await TemplateManager.generateFeaturePrint(from: variant) else {
                debugLog("feature print missing for position image")
                continue
            }

            let frontDistances = await calculateDistances(to: featurePrint, templates: frontTemplates)
            let backDistances = await calculateDistances(to: featurePrint, templates: backTemplates)

            guard let frontScore = topKAverage(frontDistances, k: 3),
                  let backScore = topKAverage(backDistances, k: 3) else {
                debugLog("distance missing frontCount=\(frontDistances.count) backCount=\(backDistances.count)")
                continue
            }

            let result = ConfidenceCalculator.calculateConfidence(
                frontDistance: frontScore,
                backDistance: backScore,
                calibration: calibration
            )
            let rank = confidenceRank(for: result.side)
            if rank < bestRank || (rank == bestRank && result.1 > bestResult.1) {
                bestRank = rank
                bestResult = result
            }
        }

        return bestResult
    }
    
    static func matchAllCoins(
        roiImages: [(UIImage, Int)],
        frontTemplates: [VNFeaturePrintObservation],
        backTemplates: [VNFeaturePrintObservation],
        calibration: ConfidenceCalculator.Calibration = .default
    ) async -> [CoinResult] {
        var results: [CoinResult] = []
        
        for (image, position) in roiImages {
            let (side, confidence) = await matchCoin(
                image: image,
                frontTemplates: frontTemplates,
                backTemplates: backTemplates,
                calibration: calibration
            )
            
            let yinYang: YinYang
            switch side {
            case .front:
                yinYang = .yin
            case .back:
                yinYang = .yang
            case .uncertain, .invalid:
                yinYang = .yang
            }
            
            let result = CoinResult(
                position: position,
                yinYang: yinYang,
                side: side,
                confidence: confidence
            )
            
            results.append(result)
        }
        
        return results.sorted { $0.position < $1.position }
    }

    static func matchAllCoinCandidates(
        roiCandidates: [(Int, [UIImage])],
        frontTemplates: [VNFeaturePrintObservation],
        backTemplates: [VNFeaturePrintObservation],
        calibration: ConfidenceCalculator.Calibration = .default,
        frontDescriptors: [[Float]] = [],
        backDescriptors: [[Float]] = [],
        descriptorCalibration: DescriptorCalibration = .default
    ) async -> [CoinResult] {
        var results: [CoinResult] = []

        for (position, candidates) in roiCandidates {
            let (side, confidence) = await matchBestCoin(
                candidates: candidates,
                frontTemplates: frontTemplates,
                backTemplates: backTemplates,
                calibration: calibration,
                frontDescriptors: frontDescriptors,
                backDescriptors: backDescriptors,
                descriptorCalibration: descriptorCalibration
            )

            let yinYang: YinYang
            switch side {
            case .front:
                yinYang = .yin
            case .back:
                yinYang = .yang
            case .uncertain, .invalid:
                yinYang = .yang
            }

            results.append(CoinResult(position: position, yinYang: yinYang, side: side, confidence: confidence))
        }

        return results.sorted { $0.position < $1.position }
    }

    private static func matchBestCoin(
        candidates: [UIImage],
        frontTemplates: [VNFeaturePrintObservation],
        backTemplates: [VNFeaturePrintObservation],
        calibration: ConfidenceCalculator.Calibration,
        frontDescriptors: [[Float]],
        backDescriptors: [[Float]],
        descriptorCalibration: DescriptorCalibration
    ) async -> (side: CoinSide, confidence: Double) {
        var bestResult: (CoinSide, Double) = (.invalid, 0.0)
        var bestRank = 2

        for candidate in candidates {
            let result: (CoinSide, Double)
            if !frontDescriptors.isEmpty && !backDescriptors.isEmpty {
                result = matchCoinByDescriptor(
                    image: candidate,
                    frontDescriptors: frontDescriptors,
                    backDescriptors: backDescriptors,
                    calibration: descriptorCalibration
                )
            } else {
                result = await matchCoin(
                    image: candidate,
                    frontTemplates: frontTemplates,
                    backTemplates: backTemplates,
                    calibration: calibration
                )
            }

            let rank = confidenceRank(for: result.0)
            if rank < bestRank || (rank == bestRank && result.1 > bestResult.1) {
                bestRank = rank
                bestResult = result
            }
        }

        return bestResult
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("FeatureMatch: \(message)")
        #endif
    }
    
    private static func calculateDistances(
        to target: VNFeaturePrintObservation,
        templates: [VNFeaturePrintObservation]
    ) async -> [Float] {
        var distances: [Float] = []
        
        for template in templates {
            let distance = await calculateDistance(between: target, and: template)
            distances.append(distance)
        }
        
        return distances
    }
    
    private static func calculateDistance(
        between observation1: VNFeaturePrintObservation,
        and observation2: VNFeaturePrintObservation
    ) async -> Float {
        return await withCheckedContinuation { continuation in
            var distance: Float = 0.0
            
            do {
                try observation1.computeDistance(&distance, to: observation2)
                continuation.resume(returning: distance)
            } catch {
                print("Distance calculation error: \(error.localizedDescription)")
                continuation.resume(returning: Float.greatestFiniteMagnitude)
            }
        }
    }

    private static func topKAverage(_ values: [Float], k: Int) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = min(k, sorted.count)
        let sum = sorted.prefix(count).reduce(0, +)
        return sum / Float(count)
    }

    private static func confidenceRank(for side: CoinSide) -> Int {
        switch side {
        case .front, .back:
            return 0
        case .uncertain:
            return 1
        case .invalid:
            return 2
        }
    }

    static func calibrateDescriptors(
        frontDescriptors: [[Float]],
        backDescriptors: [[Float]]
    ) -> DescriptorCalibration {
        let intra = pairwiseSimilarities(in: frontDescriptors) + pairwiseSimilarities(in: backDescriptors)
        let inter = crossSimilarities(front: frontDescriptors, back: backDescriptors)

        guard let intraMedian = median(intra),
              let interMedian = median(inter) else {
            return .default
        }

        let separation = max(intraMedian - interMedian, 0.02)
        let minGap = max(0.03, separation * 0.35)
        let minScore = max(0.55, (intraMedian + interMedian) / 2)

        return DescriptorCalibration(minGap: minGap, minScore: minScore)
    }

    private static func matchCoinByDescriptor(
        image: UIImage,
        frontDescriptors: [[Float]],
        backDescriptors: [[Float]],
        calibration: DescriptorCalibration
    ) -> (CoinSide, Double) {
        let variants = ImageProcessor.rotatedVariants(for: image)
        var bestResult: (CoinSide, Double) = (.invalid, 0.0)
        var bestRank = 2

        for variant in variants {
            guard let descriptor = ImageProcessor.coinDescriptor(for: variant) else { continue }

            guard let frontScore = bestSimilarity(descriptor, templates: frontDescriptors),
                  let backScore = bestSimilarity(descriptor, templates: backDescriptors) else {
                continue
            }

            let gap = abs(frontScore - backScore)
            let best = max(frontScore, backScore)
            guard best.isFinite else { continue }

            let result: (CoinSide, Double)
            if gap < calibration.minGap || best < calibration.minScore {
                result = (.uncertain, Double(best))
            } else {
                result = frontScore >= backScore
                    ? (.front, Double(best))
                    : (.back, Double(best))
            }

            let rank = confidenceRank(for: result.0)
            if rank < bestRank || (rank == bestRank && result.1 > bestResult.1) {
                bestRank = rank
                bestResult = result
            }
        }

        return bestResult
    }

    private static func bestSimilarity(
        _ descriptor: [Float],
        templates: [[Float]]
    ) -> Float? {
        guard !templates.isEmpty else { return nil }
        var best: Float = -Float.greatestFiniteMagnitude
        for template in templates {
            guard descriptor.count == template.count else { continue }
            let sim = cosineSimilarity(descriptor, template)
            if sim > best {
                best = sim
            }
        }
        return best.isFinite ? best : nil
    }

    private static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        let count = min(a.count, b.count)
        for i in 0..<count {
            sum += a[i] * b[i]
        }
        return sum
    }

    private static func pairwiseSimilarities(in templates: [[Float]]) -> [Float] {
        guard templates.count >= 2 else { return [] }
        var values: [Float] = []
        for i in 0..<(templates.count - 1) {
            for j in (i + 1)..<templates.count {
                values.append(cosineSimilarity(templates[i], templates[j]))
            }
        }
        return values
    }

    private static func crossSimilarities(front: [[Float]], back: [[Float]]) -> [Float] {
        guard !front.isEmpty, !back.isEmpty else { return [] }
        var values: [Float] = []
        for f in front {
            for b in back {
                values.append(cosineSimilarity(f, b))
            }
        }
        return values
    }

    private static func median(_ values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
