import Foundation
import Vision
import UIKit
import CoreML

class FeatureMatchService {
    private static let minDecisiveConfidence = 0.58
    private static let coreMLModelName = "CoinSideClassifier"
    private static var cachedCoreMLModel: VNCoreMLModel?

    struct DescriptorCalibration {
        let minGap: Float
        let minScore: Float

        static let `default` = DescriptorCalibration(minGap: 0.05, minScore: 0.55)
    }

    struct RingCalibration {
        let minGap: Float
        let minScore: Float
        let angularBins: Int

        static let `default` = RingCalibration(minGap: 0.02, minScore: 0.52, angularBins: 180)
    }

    struct TextCalibration {
        let frontMean: Double
        let backMean: Double
        let decisionGap: Double
        let minSeparation: Double
        let enabled: Bool

        static let `default` = TextCalibration(
            frontMean: 0.62,
            backMean: 0.36,
            decisionGap: 0.04,
            minSeparation: 0.10,
            enabled: true
        )

        static let disabled = TextCalibration(
            frontMean: 0.5,
            backMean: 0.5,
            decisionGap: 0.08,
            minSeparation: 0.12,
            enabled: false
        )
    }

    static func matchCoin(
        image: UIImage,
        frontTemplates: [VNFeaturePrintObservation],
        backTemplates: [VNFeaturePrintObservation],
        calibration: ConfidenceCalculator.Calibration = .default
    ) async -> (side: CoinSide, confidence: Double) {
        let processed = ImageProcessor.prepareCoinForMatching(image)
        var variants = ImageProcessor.rotatedVariants(for: processed)
        variants.append(ImageProcessor.applyColorControls(processed, contrast: 1.25, brightness: 0.04))
        variants.append(ImageProcessor.applyColorControls(processed, contrast: 0.9, brightness: -0.04))

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
        descriptorCalibration: DescriptorCalibration = .default,
        frontRingDescriptors: [[Float]] = [],
        backRingDescriptors: [[Float]] = [],
        ringCalibration: RingCalibration = .default,
        textCalibration: TextCalibration = .default
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
                descriptorCalibration: descriptorCalibration,
                frontRingDescriptors: frontRingDescriptors,
                backRingDescriptors: backRingDescriptors,
                ringCalibration: ringCalibration,
                textCalibration: textCalibration
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
        descriptorCalibration: DescriptorCalibration,
        frontRingDescriptors: [[Float]],
        backRingDescriptors: [[Float]],
        ringCalibration: RingCalibration,
        textCalibration: TextCalibration
    ) async -> (side: CoinSide, confidence: Double) {
        var bestResult: (CoinSide, Double) = (.invalid, 0.0)
        var bestRank = 2
        var candidateResults: [(CoinSide, Double)] = []

        for candidate in candidates {
            var merged: (CoinSide, Double)
            let hasDescriptors = !frontDescriptors.isEmpty && !backDescriptors.isEmpty
            let hasFeatureTemplates = !frontTemplates.isEmpty && !backTemplates.isEmpty
            let hasRingDescriptors = !frontRingDescriptors.isEmpty && !backRingDescriptors.isEmpty
            let ringResult: (CoinSide, Double)?
            if hasRingDescriptors {
                ringResult = matchCoinByRingDescriptor(
                    image: candidate,
                    frontDescriptors: frontRingDescriptors,
                    backDescriptors: backRingDescriptors,
                    calibration: ringCalibration
                )
            } else {
                ringResult = nil
            }

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
                if let ringResult {
                    merged = mergeWithRingResult(merged, ringResult)
                }
            } else if hasDescriptors {
                merged = matchCoinByDescriptor(
                    image: candidate,
                    frontDescriptors: frontDescriptors,
                    backDescriptors: backDescriptors,
                    calibration: descriptorCalibration
                )
                if let ringResult {
                    merged = mergeWithRingResult(merged, ringResult)
                }
            } else if hasFeatureTemplates {
                merged = await matchCoin(
                    image: candidate,
                    frontTemplates: frontTemplates,
                    backTemplates: backTemplates,
                    calibration: calibration
                )
                if let ringResult {
                    merged = mergeWithRingResult(merged, ringResult)
                }
            } else if let ringResult {
                merged = ringResult
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

        let textResult: (CoinSide, Double)
        let modelResult: (CoinSide, Double)?
        if let anchor = candidates.first {
            textResult = await matchCoinByTextEvidence(
                image: anchor,
                calibration: textCalibration
            )
            modelResult = await matchCoinByCoreML(image: anchor)
        } else {
            textResult = (.invalid, 0.0)
            modelResult = nil
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
                var merged = mergeWithTextResult(consensus, textResult)
                if let modelResult {
                    merged = mergeWithModelResult(merged, modelResult)
                }
                return merged
            }
        }

        var merged = mergeWithTextResult(bestResult, textResult)
        if let modelResult {
            merged = mergeWithModelResult(merged, modelResult)
        }
        return merged
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

        let separation = max(intraMedian - interMedian, 0.01)
        let minGap = min(max(0.02, separation * 0.30), 0.07)
        let midpoint = (intraMedian + interMedian) / 2
        let softened = midpoint - max(0.04, separation * 0.15)
        let minScore = min(max(0.52, softened), 0.82)

        return DescriptorCalibration(minGap: minGap, minScore: minScore)
    }

    static func calibrateRingDescriptors(
        frontDescriptors: [[Float]],
        backDescriptors: [[Float]],
        angularBins: Int = 180
    ) -> RingCalibration {
        let intra = pairwiseRingSimilarities(in: frontDescriptors, angularBins: angularBins)
            + pairwiseRingSimilarities(in: backDescriptors, angularBins: angularBins)
        let inter = crossRingSimilarities(
            front: frontDescriptors,
            back: backDescriptors,
            angularBins: angularBins
        )

        guard let intraMedian = median(intra),
              let interMedian = median(inter) else {
            return RingCalibration.default
        }

        let separation = max(intraMedian - interMedian, 0.01)
        let minGap = min(max(0.014, separation * 0.55), 0.09)
        let midpoint = (intraMedian + interMedian) / 2
        let minScore = min(max(0.50, midpoint - separation * 0.20), 0.90)

        return RingCalibration(
            minGap: minGap,
            minScore: minScore,
            angularBins: angularBins
        )
    }

    static func calibrateText(
        frontImages: [UIImage],
        backImages: [UIImage]
    ) async -> TextCalibration {
        guard !frontImages.isEmpty, !backImages.isEmpty else {
            return .default
        }

        var frontScores: [Double] = []
        var backScores: [Double] = []

        for image in frontImages {
            let score = await textPresenceScore(for: image)
            if score.isFinite {
                frontScores.append(score)
            }
        }
        for image in backImages {
            let score = await textPresenceScore(for: image)
            if score.isFinite {
                backScores.append(score)
            }
        }

        guard !frontScores.isEmpty, !backScores.isEmpty else {
            return .default
        }

        let frontMean = frontScores.reduce(0, +) / Double(frontScores.count)
        let backMean = backScores.reduce(0, +) / Double(backScores.count)
        let separation = frontMean - backMean

        if separation < 0.06 {
            return TextCalibration(
                frontMean: frontMean,
                backMean: backMean,
                decisionGap: 0.08,
                minSeparation: 0.12,
                enabled: false
            )
        }

        let decisionGap = min(max(0.03, separation * 0.20), 0.10)
        return TextCalibration(
            frontMean: frontMean,
            backMean: backMean,
            decisionGap: decisionGap,
            minSeparation: 0.08,
            enabled: true
        )
    }

    private static func matchCoinByRingDescriptor(
        image: UIImage,
        frontDescriptors: [[Float]],
        backDescriptors: [[Float]],
        calibration: RingCalibration
    ) -> (CoinSide, Double) {
        guard let descriptor = ImageProcessor.coinRingDescriptor(
            for: image,
            angularSamples: calibration.angularBins
        ) else {
            return (.invalid, 0.0)
        }

        guard let frontScore = topKCircularSimilarity(
            descriptor,
            templates: frontDescriptors,
            angularBins: calibration.angularBins,
            k: 5
        ),
        let backScore = topKCircularSimilarity(
            descriptor,
            templates: backDescriptors,
            angularBins: calibration.angularBins,
            k: 5
        ) else {
            return (.invalid, 0.0)
        }

        return classifyRingScores(
            frontScore: frontScore,
            backScore: backScore,
            calibration: calibration
        )
    }

    private static func classifyRingScores(
        frontScore: Float,
        backScore: Float,
        calibration: RingCalibration
    ) -> (CoinSide, Double) {
        let gap = abs(frontScore - backScore)
        let best = max(frontScore, backScore)
        guard best.isFinite else { return (.invalid, 0.0) }

        if best >= calibration.minScore, gap >= calibration.minGap {
            let side: CoinSide = frontScore >= backScore ? .front : .back
            return (side, Double(best))
        }

        if best < (calibration.minScore - 0.10) {
            return (.invalid, Double(best))
        }

        return (.uncertain, Double(best))
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

            guard let frontScore = topKSimilarity(descriptor, templates: frontDescriptors, k: 5),
                  let backScore = topKSimilarity(descriptor, templates: backDescriptors, k: 5) else {
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

        let isStrongScore = best >= (calibration.minScore + 0.07)
        let hasStrongGap = gap >= calibration.minGap
        let hasRelaxedGap = gap >= (calibration.minGap * 0.55)

        if hasStrongGap || (isStrongScore && hasRelaxedGap) {
            let side: CoinSide = frontScore >= backScore ? .front : .back
            return (side, Double(best))
        }

        if best < (calibration.minScore - 0.16) {
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

        if descriptorDecisive && featureResult.0 == .invalid {
            return descriptorConfidence >= 0.70
                ? (descriptorResult.0, descriptorConfidence)
                : (.uncertain, descriptorConfidence)
        }

        if descriptorDecisive {
            return descriptorConfidence >= 0.74
                ? descriptorResult
                : (.uncertain, descriptorConfidence)
        }

        if featureDecisive {
            return featureResult
        }

        return preferredResult(descriptorResult, featureResult)
    }

    private static func mergeWithRingResult(
        _ base: (CoinSide, Double),
        _ ring: (CoinSide, Double)
    ) -> (CoinSide, Double) {
        let baseDecisive = isDecisive(base.0)
        let ringDecisive = isDecisive(ring.0)
        let baseConfidence = normalizedConfidence(base.1)
        let ringConfidence = normalizedConfidence(ring.1)

        if baseDecisive && ringDecisive {
            if base.0 == ring.0 {
                return (base.0, (baseConfidence + ringConfidence) / 2)
            }
            if ringConfidence - baseConfidence >= 0.08 {
                return (ring.0, ringConfidence)
            }
            if baseConfidence - ringConfidence >= 0.10 {
                return (base.0, baseConfidence)
            }
            return (.uncertain, max(baseConfidence, ringConfidence))
        }

        if ringDecisive && !baseDecisive {
            return ringConfidence >= 0.66 ? (ring.0, ringConfidence) : (.uncertain, ringConfidence)
        }

        if baseDecisive {
            return (base.0, baseConfidence)
        }

        return preferredResult(
            (base.0, baseConfidence),
            (ring.0, ringConfidence)
        )
    }

    private static func mergeWithTextResult(
        _ base: (CoinSide, Double),
        _ text: (CoinSide, Double)
    ) -> (CoinSide, Double) {
        let baseDecisive = isDecisive(base.0)
        let textDecisive = isDecisive(text.0)
        let baseConfidence = normalizedConfidence(base.1)
        let textConfidence = normalizedConfidence(text.1)

        if baseDecisive && textDecisive {
            if base.0 == text.0 {
                return (base.0, (baseConfidence * 0.75) + (textConfidence * 0.25))
            }
            if textConfidence >= 0.84, textConfidence - baseConfidence >= 0.10 {
                return (text.0, textConfidence)
            }
            if baseConfidence >= 0.78, baseConfidence - textConfidence >= 0.10 {
                return (base.0, baseConfidence)
            }
            return (.uncertain, max(baseConfidence, textConfidence))
        }

        if textDecisive && !baseDecisive {
            return textConfidence >= 0.64
                ? (text.0, textConfidence)
                : (.uncertain, textConfidence)
        }

        if baseDecisive {
            return (base.0, baseConfidence)
        }

        return preferredResult(
            (base.0, baseConfidence),
            (text.0, textConfidence)
        )
    }

    private static func mergeWithModelResult(
        _ base: (CoinSide, Double),
        _ model: (CoinSide, Double)
    ) -> (CoinSide, Double) {
        let baseDecisive = isDecisive(base.0)
        let modelDecisive = isDecisive(model.0)
        let baseConfidence = normalizedConfidence(base.1)
        let modelConfidence = normalizedConfidence(model.1)

        if modelDecisive && !baseDecisive {
            return modelConfidence >= 0.65
                ? (model.0, modelConfidence)
                : (.uncertain, modelConfidence)
        }

        if baseDecisive && modelDecisive {
            if base.0 == model.0 {
                return (base.0, (baseConfidence * 0.65) + (modelConfidence * 0.35))
            }
            if modelConfidence >= 0.90, modelConfidence - baseConfidence >= 0.12 {
                return (model.0, modelConfidence)
            }
            if baseConfidence >= 0.80 {
                return (base.0, baseConfidence)
            }
            return (.uncertain, max(baseConfidence, modelConfidence))
        }

        return base
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

    private static func matchCoinByTextEvidence(
        image: UIImage,
        calibration: TextCalibration
    ) async -> (CoinSide, Double) {
        guard calibration.enabled else {
            return (.uncertain, 0.5)
        }

        let score = await textPresenceScore(for: image)
        guard score.isFinite else { return (.invalid, 0.0) }

        let separation = calibration.frontMean - calibration.backMean
        guard separation >= calibration.minSeparation else {
            return (.uncertain, 0.5)
        }

        let split = (calibration.frontMean + calibration.backMean) / 2
        if score >= split + calibration.decisionGap {
            let confidence = min(
                0.95,
                0.55 + ((score - split) / max(1.0 - split, 0.08)) * 0.40
            )
            return (.front, confidence)
        }

        if score <= split - calibration.decisionGap {
            let confidence = min(
                0.95,
                0.55 + ((split - score) / max(split, 0.08)) * 0.40
            )
            return (.back, confidence)
        }

        let uncertainty = 0.50 + min(0.10, abs(score - split))
        return (.uncertain, uncertainty)
    }

    private static func textPresenceScore(for image: UIImage) async -> Double {
        let prepared = ImageProcessor.prepareCoinForMatching(
            image,
            targetSize: CGSize(width: 320, height: 320)
        )
        let ringImage = ImageProcessor.polarUnwrappedRingImage(
            for: prepared,
            innerRadiusRatio: 0.20,
            outerRadiusRatio: 0.49,
            angularSamples: 240,
            radialSamples: 40
        ) ?? prepared

        let ringScore = await textSignalScore(on: ringImage)
        let fullScore = await textSignalScore(on: prepared)
        return min(max((ringScore * 0.72) + (fullScore * 0.28), 0), 1)
    }

    private static func textSignalScore(on image: UIImage) async -> Double {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(returning: 0.0)
                    return
                }

                let recognize = VNRecognizeTextRequest()
                recognize.recognitionLevel = .accurate
                recognize.usesLanguageCorrection = false
                recognize.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
                recognize.minimumTextHeight = 0.03

                let detect = VNDetectTextRectanglesRequest()
                detect.reportCharacterBoxes = false

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([recognize, detect])
                } catch {
                    continuation.resume(returning: 0.0)
                    return
                }

                let textObservations = recognize.results ?? []
                let rectObservations = detect.results ?? []

                var recognizedCount = 0
                var confidenceSum = 0.0
                var charEvidence = 0.0
                for observation in textObservations {
                    guard let top = observation.topCandidates(1).first else { continue }
                    recognizedCount += 1
                    confidenceSum += Double(top.confidence)
                    charEvidence += Double(min(top.string.count, 4)) / 4.0
                }

                var rectAreaSum = 0.0
                for rect in rectObservations {
                    let box = rect.boundingBox
                    rectAreaSum += Double(box.width * box.height)
                }

                let recognizeScore: Double
                if recognizedCount > 0 {
                    let averageConfidence = confidenceSum / Double(recognizedCount)
                    let density = min(1.0, charEvidence / Double(max(recognizedCount, 1)))
                    recognizeScore = min(1.0, (averageConfidence * 0.70) + (density * 0.30))
                } else {
                    recognizeScore = 0.0
                }

                let rectCountScore = min(1.0, Double(rectObservations.count) * 0.15)
                let rectCoverageScore = min(1.0, rectAreaSum * 2.8)
                let rectScore = min(1.0, (rectCountScore * 0.60) + (rectCoverageScore * 0.40))

                let combined = min(1.0, (recognizeScore * 0.55) + (rectScore * 0.45))
                continuation.resume(returning: combined)
            }
        }
    }

    private static func matchCoinByCoreML(
        image: UIImage
    ) async -> (CoinSide, Double)? {
        guard let model = coreMLModel() else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let prepared = ImageProcessor.prepareCoinForMatching(
                image,
                targetSize: CGSize(width: 224, height: 224)
            )
            guard let cgImage = prepared.cgImage else {
                continuation.resume(returning: nil)
                return
            }

            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
                return
            }

            guard let observations = request.results as? [VNClassificationObservation],
                  let top = observations.first else {
                continuation.resume(returning: nil)
                return
            }

            let side = mapModelIdentifierToSide(top.identifier)
            let confidence = normalizedConfidence(Double(top.confidence))
            continuation.resume(returning: (side, confidence))
        }
    }

    private static func coreMLModel() -> VNCoreMLModel? {
        if let cachedCoreMLModel {
            return cachedCoreMLModel
        }

        guard let url = Bundle.main.url(
            forResource: coreMLModelName,
            withExtension: "mlmodelc"
        ) else {
            return nil
        }

        guard let compiledModel = try? MLModel(contentsOf: url),
              let visionModel = try? VNCoreMLModel(for: compiledModel) else {
            return nil
        }

        cachedCoreMLModel = visionModel
        debugLog("coreml model loaded: \(coreMLModelName)")
        return visionModel
    }

    private static func mapModelIdentifierToSide(_ identifier: String) -> CoinSide {
        let normalized = identifier.lowercased()
        if normalized.contains("front") || identifier.contains("字") || identifier.contains("阴") {
            return .front
        }
        if normalized.contains("back") || identifier.contains("图") || identifier.contains("阳") {
            return .back
        }
        return .uncertain
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

    private static func topKSimilarity(
        _ descriptor: [Float],
        templates: [[Float]],
        k: Int
    ) -> Float? {
        guard !templates.isEmpty, k > 0 else { return nil }
        var similarities: [Float] = []
        similarities.reserveCapacity(templates.count)

        for template in templates {
            guard descriptor.count == template.count else { continue }
            let sim = cosineSimilarity(descriptor, template)
            if sim.isFinite {
                similarities.append(sim)
            }
        }

        guard !similarities.isEmpty else { return nil }
        let sorted = similarities.sorted(by: >)
        let count = min(k, sorted.count)
        let sum = sorted.prefix(count).reduce(0, +)
        return sum / Float(count)
    }

    private static func bestCircularSimilarity(
        _ descriptor: [Float],
        templates: [[Float]],
        angularBins: Int
    ) -> Float? {
        guard !templates.isEmpty, descriptor.count == angularBins * 2 else { return nil }
        var best: Float = -Float.greatestFiniteMagnitude
        for template in templates where template.count == descriptor.count {
            let similarity = circularSimilarity(
                descriptor,
                template,
                angularBins: angularBins
            )
            if similarity > best {
                best = similarity
            }
        }
        return best.isFinite ? best : nil
    }

    private static func topKCircularSimilarity(
        _ descriptor: [Float],
        templates: [[Float]],
        angularBins: Int,
        k: Int
    ) -> Float? {
        guard !templates.isEmpty,
              descriptor.count == angularBins * 2,
              k > 0 else { return nil }

        var scores: [Float] = []
        scores.reserveCapacity(templates.count)
        for template in templates where template.count == descriptor.count {
            let score = circularSimilarity(
                descriptor,
                template,
                angularBins: angularBins
            )
            if score.isFinite {
                scores.append(score)
            }
        }

        guard !scores.isEmpty else { return nil }
        let sorted = scores.sorted(by: >)
        let count = min(k, sorted.count)
        let sum = sorted.prefix(count).reduce(0, +)
        return sum / Float(count)
    }

    private static func circularSimilarity(
        _ lhs: [Float],
        _ rhs: [Float],
        angularBins: Int
    ) -> Float {
        guard lhs.count == rhs.count, lhs.count == angularBins * 2, angularBins > 0 else {
            return -Float.greatestFiniteMagnitude
        }

        let ringA = Array(lhs[0..<angularBins])
        let ringB = Array(rhs[0..<angularBins])
        let intensityA = Array(lhs[angularBins..<(angularBins * 2)])
        let intensityB = Array(rhs[angularBins..<(angularBins * 2)])

        let step = max(1, angularBins / 45)
        var best: Float = -Float.greatestFiniteMagnitude

        var shift = 0
        while shift < angularBins {
            var ringDot: Float = 0
            var intensityDot: Float = 0
            for index in 0..<angularBins {
                let shifted = (index + shift) % angularBins
                ringDot += ringA[shifted] * ringB[index]
                intensityDot += intensityA[shifted] * intensityB[index]
            }
            let score = (ringDot * 0.70) + (intensityDot * 0.30)
            if score > best {
                best = score
            }
            shift += step
        }

        return best
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

    private static func pairwiseRingSimilarities(
        in templates: [[Float]],
        angularBins: Int
    ) -> [Float] {
        guard templates.count >= 2 else { return [] }
        var values: [Float] = []
        for i in 0..<(templates.count - 1) {
            for j in (i + 1)..<templates.count {
                let score = circularSimilarity(
                    templates[i],
                    templates[j],
                    angularBins: angularBins
                )
                if score.isFinite {
                    values.append(score)
                }
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

    private static func crossRingSimilarities(
        front: [[Float]],
        back: [[Float]],
        angularBins: Int
    ) -> [Float] {
        guard !front.isEmpty, !back.isEmpty else { return [] }
        var values: [Float] = []
        for f in front {
            for b in back {
                let score = circularSimilarity(
                    f,
                    b,
                    angularBins: angularBins
                )
                if score.isFinite {
                    values.append(score)
                }
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
