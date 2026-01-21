import Foundation
import Vision
import CoreGraphics

class ConfidenceCalculator {
    private static let maxMatchDistance: Float = 1.5
    private static let minDistanceGap: Float = 0.005

    static func calculateConfidence(
        frontDistance: Float,
        backDistance: Float
    ) -> (side: CoinSide, confidence: Double) {
        let totalDistance = frontDistance + backDistance
        
        guard totalDistance > 0 else {
            return (.invalid, 0.0)
        }

        let minDistance = min(frontDistance, backDistance)
        let distanceGap = abs(frontDistance - backDistance)

        guard minDistance.isFinite,
              minDistance <= maxMatchDistance,
              distanceGap >= minDistanceGap else {
            debugLog("invalid match minDistance=\(minDistance) gap=\(distanceGap)")
            return (.invalid, 0.0)
        }
        
        let frontConfidence = 1.0 - Double(frontDistance / totalDistance)
        let backConfidence = 1.0 - Double(backDistance / totalDistance)

        let confidenceThreshold: Double = 0.35
        let baseConfidence = max(frontConfidence, backConfidence)

        if baseConfidence < confidenceThreshold {
            debugLog("low confidence base=\(baseConfidence) threshold=\(confidenceThreshold)")
            return (.invalid, baseConfidence)
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
    
    static func isCoinValid(contourObservation: Any) -> Bool {
        // For iOS 16+, we need to use different contour detection methods
        // This is a placeholder that accepts any observation for now
        // TODO: Implement proper contour validation using VNDetectContourRequest
        return true
    }
}
