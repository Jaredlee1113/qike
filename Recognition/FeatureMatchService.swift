import Foundation
import Vision
import UIKit

class FeatureMatchService {
    private static let minDecisiveConfidence = 0.62

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
        var candidateResults: [(CoinSide, Double)] = []

        for candidate in candidates {
            let merged: (CoinSide, Double)
            let hasDescriptors = !frontDescriptors.isEmpty && !backDescriptors.isEmpty
            let hasFeatureTemplates = !frontTemplates.isEmpty && !backTemplates.isEmpty

            if hasDescriptors && hasFeatureTemplates {
                let descriptorResult = matchCoinByDescriptor(
                    image: candidate,
                    frontDescriptors: frontDescriptors,
                    backDescriptors: backDescriptors,
                    calibration: descriptorCalibration
                )
                let featureResult = await matchCoin(
                    image: candidate,
                    frontTemplates: frontTemplates,
                    backTemplates: backTemplates,
                    calibration: calibration
                )
                merged = mergeDescriptorAndFeatureResult(
                    descriptorResult,
                    featureResult
                )
            } else if hasDescriptors {
                merged = matchCoinByDescriptor(
                    image: candidate,
                    frontDescriptors: frontDescriptors,
                    backDescriptors: backDescriptors,
                    calibration: descriptorCalibration
                )
            } else {
                merged = await matchCoin(
                    image: candidate,
                    frontTemplates: frontTemplates,
                    backTemplates: backTemplates,
                    calibration: calibration
                )
            }

            let adjusted = reliabilityAdjusted(
                merged,
                minConfidence: minDecisiveConfidence
            )
            candidateResults.append(adjusted)

            let rank = confidenceRank(for: adjusted.0)
            if rank < bestRank || (rank == bestRank && adjusted.1 > bestResult.1) {
                bestRank = rank
                bestResult = adjusted
            }
        }

        if !candidateResults.isEmpty {
            let frontEvidence = candidateResults
                .filter { $0.0 == .front }
                .reduce(0.0) { $0 + normalizedConfidence($1.1) }
            let backEvidence = candidateResults
                .filter { $0.0 == .back }
                .reduce(0.0) { $0 + normalizedConfidence($1.1) }
            let frontCount = candidateResults.filter { $0.0 == .front }.count
            let backCount = candidateResults.filter { $0.0 == .back }.count
            let consensus = resolveCandidateEvidence(
                frontEvidence: frontEvidence,
                backEvidence: backEvidence,
                frontCount: frontCount,
                backCount: backCount
            )
            if consensus.0 == .front || consensus.0 == .back {
                return consensus
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

            let result = classifyDescriptorScores(
                frontScore: frontScore,
                backScore: backScore,
                calibration: calibration
            )

            let rank = confidenceRank(for: result.0)
            if rank < bestRank || (rank == bestRank && result.1 > bestResult.1) {
                bestRank = rank
                bestResult = result
            }
        }

        return bestResult
    }

    static func classifyDescriptorScores(
        frontScore: Float,
        backScore: Float,
        calibration: DescriptorCalibration
    ) -> (CoinSide, Double) {
        let gap = abs(frontScore - backScore)
        let best = max(frontScore, backScore)
        guard best.isFinite else { return (.invalid, 0.0) }

        let isStrongScore = best >= (calibration.minScore + 0.10)
        let hasStrongGap = gap >= calibration.minGap
        let hasRelaxedGap = gap >= (calibration.minGap * 0.70)

        if hasStrongGap || (isStrongScore && hasRelaxedGap) {
            let side: CoinSide = frontScore >= backScore ? .front : .back
            return (side, Double(best))
        }

        if best < (calibration.minScore - 0.08) {
            return (.invalid, Double(best))
        }

        return (.uncertain, Double(best))
    }

    static func resolveCandidateEvidence(
        frontEvidence: Double,
        backEvidence: Double,
        frontCount: Int,
        backCount: Int
    ) -> (CoinSide, Double) {
        let totalEvidence = frontEvidence + backEvidence
        guard totalEvidence > 0 else { return (.invalid, 0.0) }

        let dominantSide: CoinSide = frontEvidence >= backEvidence ? .front : .back
        let dominantEvidence = max(frontEvidence, backEvidence)
        let confidence = dominantEvidence / totalEvidence
        let margin = abs(frontEvidence - backEvidence) / totalEvidence
        let supportCount = max(frontCount, backCount)

        if margin < 0.12 || supportCount < 2 {
            return (.uncertain, confidence)
        }
        return (dominantSide, confidence)
    }

    private static func preferredResult(
        _ lhs: (CoinSide, Double),
        _ rhs: (CoinSide, Double)
    ) -> (CoinSide, Double) {
        let lhsRank = confidenceRank(for: lhs.0)
        let rhsRank = confidenceRank(for: rhs.0)
        if rhsRank < lhsRank {
            return rhs
        }
        if lhsRank < rhsRank {
            return lhs
        }
        return rhs.1 > lhs.1 ? rhs : lhs
    }

    private static func mergeDescriptorAndFeatureResult(
        _ descriptorResult: (CoinSide, Double),
        _ featureResult: (CoinSide, Double)
    ) -> (CoinSide, Double) {
        let descriptorDecisive = isDecisive(descriptorResult.0)
        let featureDecisive = isDecisive(featureResult.0)
        let descriptorConfidence = normalizedConfidence(descriptorResult.1)
        let featureConfidence = normalizedConfidence(featureResult.1)

        if descriptorDecisive && featureDecisive {
            if descriptorResult.0 == featureResult.0 {
                return (
                    descriptorResult.0,
                    (descriptorConfidence + featureConfidence) / 2
                )
            }
            if featureConfidence - descriptorConfidence >= 0.10 {
                return (featureResult.0, featureConfidence)
            }
            if descriptorConfidence - featureConfidence >= 0.14 {
                return (descriptorResult.0, descriptorConfidence)
            }
            return (.uncertain, max(descriptorConfidence, featureConfidence))
        }

        if descriptorDecisive {
            return descriptorConfidence >= 0.82
                ? descriptorResult
                : (.uncertain, descriptorConfidence)
        }

        if featureDecisive {
            return featureResult
        }

        return preferredResult(descriptorResult, featureResult)
    }

    private static func reliabilityAdjusted(
        _ result: (CoinSide, Double),
        minConfidence: Double
    ) -> (CoinSide, Double) {
        guard isDecisive(result.0) else {
            return (result.0, normalizedConfidence(result.1))
        }
        let confidence = normalizedConfidence(result.1)
        guard confidence >= minConfidence else {
            return (.uncertain, confidence)
        }
        return (result.0, confidence)
    }

    private static func isDecisive(_ side: CoinSide) -> Bool {
        side == .front || side == .back
    }

    private static func normalizedConfidence(_ value: Double) -> Double {
        min(max(value, 0), 1)
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
