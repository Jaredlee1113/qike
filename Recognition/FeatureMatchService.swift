import Foundation
import Vision
import UIKit

class FeatureMatchService {
    static func matchCoin(
        image: UIImage,
        frontTemplates: [VNFeaturePrintObservation],
        backTemplates: [VNFeaturePrintObservation]
    ) async -> (side: CoinSide, confidence: Double) {
        let processed = ImageProcessor.prepareForMatching(image)
        guard let featurePrint = await TemplateManager.generateFeaturePrint(from: processed) else {
            debugLog("feature print missing for position image")
            return (.invalid, 0.0)
        }
        
        let frontDistances = await calculateDistances(to: featurePrint, templates: frontTemplates)
        let backDistances = await calculateDistances(to: featurePrint, templates: backTemplates)

        let topFront = Array(frontDistances.sorted().prefix(3))
        let topBack = Array(backDistances.sorted().prefix(3))
        debugLog("topFront=\(topFront) topBack=\(topBack)")
        
        guard let minFrontDistance = frontDistances.min(),
              let minBackDistance = backDistances.min() else {
            debugLog("distance missing frontCount=\(frontDistances.count) backCount=\(backDistances.count)")
            return (.invalid, 0.0)
        }

        let result = ConfidenceCalculator.calculateConfidence(
            frontDistance: minFrontDistance,
            backDistance: minBackDistance
        )
        let totalDistance = minFrontDistance + minBackDistance
        let frontConfidence = totalDistance > 0 ? 1.0 - Double(minFrontDistance / totalDistance) : 0.0
        let backConfidence = totalDistance > 0 ? 1.0 - Double(minBackDistance / totalDistance) : 0.0
        let distanceGap = abs(minFrontDistance - minBackDistance)
        debugLog("minFront=\(minFrontDistance) minBack=\(minBackDistance) gap=\(distanceGap) frontConf=\(frontConfidence) backConf=\(backConfidence) result=\(result.side) conf=\(result.confidence)")
        return result
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

    static func matchAllCoinCandidates(
        roiCandidates: [(Int, [UIImage])],
        frontTemplates: [VNFeaturePrintObservation],
        backTemplates: [VNFeaturePrintObservation]
    ) async -> [CoinResult] {
        var results: [CoinResult] = []

        for (position, candidates) in roiCandidates {
            let (side, confidence) = await matchBestCoin(
                candidates: candidates,
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

            results.append(CoinResult(position: position, yinYang: yinYang, side: side, confidence: confidence))
        }

        return results.sorted { $0.position < $1.position }
    }

    private static func matchBestCoin(
        candidates: [UIImage],
        frontTemplates: [VNFeaturePrintObservation],
        backTemplates: [VNFeaturePrintObservation]
    ) async -> (side: CoinSide, confidence: Double) {
        var bestResult: (CoinSide, Double) = (.invalid, 0.0)

        for candidate in candidates {
            let result = await matchCoin(
                image: candidate,
                frontTemplates: frontTemplates,
                backTemplates: backTemplates
            )

            if result.confidence > bestResult.1 {
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
}
