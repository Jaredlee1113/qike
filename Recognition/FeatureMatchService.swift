import Foundation
import Vision
import UIKit

class FeatureMatchService {
    static func matchCoin(
        image: UIImage,
        frontTemplates: [VNFeaturePrintObservation],
        backTemplates: [VNFeaturePrintObservation]
    ) async -> (side: CoinSide, confidence: Double) {
        guard let featurePrint = await TemplateManager.generateFeaturePrint(from: image) else {
            return (.invalid, 0.0)
        }
        
        let frontDistances = await calculateDistances(to: featurePrint, templates: frontTemplates)
        let backDistances = await calculateDistances(to: featurePrint, templates: backTemplates)
        
        guard let minFrontDistance = frontDistances.min(),
              let minBackDistance = backDistances.min() else {
            return (.invalid, 0.0)
        }
        
        return ConfidenceCalculator.calculateConfidence(
            frontDistance: minFrontDistance,
            backDistance: minBackDistance
        )
    }
    
    static func matchAllCoins(
        roiImages: [(UIImage, Int)],
        frontTemplates: [VNFeaturePrintObservation],
        backTemplates: [VNFeaturePrintObservation]
    ) async -> [CoinResult] {
        var results: [CoinResult] = []
        
        for (image, position) in roiImages {
            let (side, confidence) = await matchCoin(
                image: image,
                frontTemplates: frontTemplates,
                backTemplates: backTemplates
            )
            
            let yinYang: YinYang
            switch side {
            case .front:
                yinYang = .yin
            case .back:
                yinYang = .yang
            case .invalid:
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
}