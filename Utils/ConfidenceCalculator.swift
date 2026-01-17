import Foundation
import Vision
import CoreGraphics

class ConfidenceCalculator {
    static func calculateConfidence(
        frontDistance: Float,
        backDistance: Float
    ) -> (side: CoinSide, confidence: Double) {
        let totalDistance = frontDistance + backDistance
        
        guard totalDistance > 0 else {
            return (.invalid, 0.0)
        }
        
        let frontConfidence = 1.0 - Double(frontDistance / totalDistance)
        let backConfidence = 1.0 - Double(backDistance / totalDistance)
        
        let confidenceThreshold: Double = 0.3
        let minConfidence = max(frontConfidence, backConfidence)
        
        if minConfidence < confidenceThreshold {
            return (.invalid, minConfidence)
        }
        
        if backConfidence > frontConfidence {
            return (.back, backConfidence)
        } else {
            return (.front, frontConfidence)
        }
    }
    
    static func isCoinValid(contourObservation: Any) -> Bool {
        // For iOS 16+, we need to use different contour detection methods
        // This is a placeholder that accepts any observation for now
        // TODO: Implement proper contour validation using VNDetectContourRequest
        return true
    }
}