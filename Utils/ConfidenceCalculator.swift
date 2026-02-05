import Foundation
import Vision
import CoreGraphics

class ConfidenceCalculator {
    struct Calibration {
        let maxMatchDistance: Float
        let minDistanceGap: Float
        let minConfidence: Double

        static let `default` = Calibration(
            maxMatchDistance: 1.5,
            minDistanceGap: 0.015,
            minConfidence: 0.45
        )
    }

    static func calculateConfidence(
        frontDistance: Float,
        backDistance: Float
    ) -> (side: CoinSide, confidence: Double) {
        calculateConfidence(
            frontDistance: frontDistance,
            backDistance: backDistance,
            calibration: .default
        )
    }

    static func calculateConfidence(
        frontDistance: Float,
        backDistance: Float,
        calibration: Calibration
    ) -> (side: CoinSide, confidence: Double) {
        let totalDistance = frontDistance + backDistance
        
        guard totalDistance > 0 else {
            return (.invalid, 0.0)
        }

        let minDistance = min(frontDistance, backDistance)
        let distanceGap = abs(frontDistance - backDistance)

        guard minDistance.isFinite else {
            debugLog("invalid match minDistance=\(minDistance) gap=\(distanceGap)")
            return (.invalid, 0.0)
        }
        
        guard minDistance <= calibration.maxMatchDistance else {
            debugLog("invalid match minDistance=\(minDistance) gap=\(distanceGap)")
            return (.invalid, 0.0)
        }
        
        let frontConfidence = 1.0 - Double(frontDistance / totalDistance)
        let backConfidence = 1.0 - Double(backDistance / totalDistance)

        let baseConfidence = max(frontConfidence, backConfidence)

        if distanceGap < calibration.minDistanceGap || baseConfidence < calibration.minConfidence {
            debugLog("uncertain match minDistance=\(minDistance) gap=\(distanceGap) base=\(baseConfidence)")
            return (.uncertain, baseConfidence)
        }
        
        if backConfidence > frontConfidence {
            return (.back, backConfidence)
        } else {
            return (.front, frontConfidence)
        }
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("Confidence: \(message)")
        #endif
    }

    static func calibrate(
        frontTemplates: [VNFeaturePrintObservation],
        backTemplates: [VNFeaturePrintObservation]
    ) -> Calibration {
        let intra = pairwiseDistances(in: frontTemplates) + pairwiseDistances(in: backTemplates)
        let inter = crossDistances(front: frontTemplates, back: backTemplates)

        guard let intraMedian = median(intra),
              let interMedian = median(inter),
              interMedian.isFinite else {
            return .default
        }

        let separation = max(interMedian - intraMedian, 0.01)
        let gap = max(0.01, separation * 0.25)
        let maxDistance = max(interMedian * 1.2, intraMedian * 1.6)

        return Calibration(
            maxMatchDistance: maxDistance,
            minDistanceGap: gap,
            minConfidence: 0.45
        )
    }

    private static func pairwiseDistances(
        in templates: [VNFeaturePrintObservation]
    ) -> [Float] {
        guard templates.count >= 2 else { return [] }
        var distances: [Float] = []
        for i in 0..<(templates.count - 1) {
            for j in (i + 1)..<templates.count {
                if let distance = safeDistance(templates[i], templates[j]) {
                    distances.append(distance)
                }
            }
        }
        return distances
    }

    private static func crossDistances(
        front: [VNFeaturePrintObservation],
        back: [VNFeaturePrintObservation]
    ) -> [Float] {
        guard !front.isEmpty, !back.isEmpty else { return [] }
        var distances: [Float] = []
        for frontTemplate in front {
            for backTemplate in back {
                if let distance = safeDistance(frontTemplate, backTemplate) {
                    distances.append(distance)
                }
            }
        }
        return distances
    }

    private static func safeDistance(
        _ lhs: VNFeaturePrintObservation,
        _ rhs: VNFeaturePrintObservation
    ) -> Float? {
        var distance: Float = 0
        do {
            try lhs.computeDistance(&distance, to: rhs)
            return distance
        } catch {
            debugLog("distance error: \(error.localizedDescription)")
            return nil
        }
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
    
    static func isCoinValid(contourObservation: Any) -> Bool {
        // For iOS 16+, we need to use different contour detection methods
        // This is a placeholder that accepts any observation for now
        // TODO: Implement proper contour validation using VNDetectContourRequest
        return true
    }
}
