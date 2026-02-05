import Foundation
import Vision
import UIKit

class TemplateManager {
    struct TemplateData: Codable {
        let featurePrints: [Data]
        let descriptors: [[Float]]
        let createdDate: Date

        enum CodingKeys: String, CodingKey {
            case featurePrints
            case descriptors
            case createdDate
        }
        
        init(
            featurePrints: [VNFeaturePrintObservation],
            descriptors: [[Float]] = [],
            createdDate: Date = Date()
        ) {
            self.featurePrints = featurePrints.compactMap { observation in
                try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
            }
            self.descriptors = descriptors
            self.createdDate = createdDate
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            featurePrints = try container.decode([Data].self, forKey: .featurePrints)
            descriptors = try container.decodeIfPresent([[Float]].self, forKey: .descriptors) ?? []
            createdDate = try container.decodeIfPresent(Date.self, forKey: .createdDate) ?? Date()
        }
        
        func getObservations() -> [VNFeaturePrintObservation] {
            return featurePrints.compactMap { data in
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
            }
        }

        func getDescriptors() -> [[Float]] {
            descriptors
        }
    }
    
    static func createTemplates(
        from images: [UIImage],
        includeFeaturePrints: Bool = false,
        useCoinDetection: Bool = false
    ) async -> TemplateData {
        var featurePrints: [VNFeaturePrintObservation] = []
        var descriptors: [[Float]] = []

        for image in images {
            let normalized = ImageProcessor.normalizeOrientation(image)
            let reduced = ImageProcessor.downscaleImage(normalized, maxDimension: 512)

            let sourceImage: UIImage
            if useCoinDetection, let detected = await CoinDetector.detectSingleCoinFast(from: reduced) {
                sourceImage = detected.maskedImage ?? detected.image
            } else {
                sourceImage = reduced
            }

            if let descriptor = ImageProcessor.coinDescriptor(for: sourceImage) {
                descriptors.append(descriptor)
            }

            if includeFeaturePrints {
                let processed = ImageProcessor.prepareCoinForMatching(sourceImage)
                if let featurePrint = await generateFeaturePrint(from: processed) {
                    featurePrints.append(featurePrint)
                }
            }
        }

        return TemplateData(featurePrints: featurePrints, descriptors: descriptors)
    }
    
    static func generateFeaturePrint(from image: UIImage) async -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false
            let resumeOnce: (VNFeaturePrintObservation?) -> Void = { value in
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: value)
            }

            let request = VNGenerateImageFeaturePrintRequest { request, error in
                if let error = error {
                    debugLog("feature print error: \(error.localizedDescription)")
                    resumeOnce(nil)
                    return
                }
                
                guard let observations = request.results as? [VNFeaturePrintObservation],
                      let featurePrint = observations.first else {
                    debugLog("feature print missing in results")
                    resumeOnce(nil)
                    return
                }
                
                resumeOnce(featurePrint)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                debugLog("feature print perform failed: \(error)")
                resumeOnce(nil)
            }
        }
    }
    
    static func serializeTemplateData(_ data: TemplateData) -> Data? {
        return try? JSONEncoder().encode(data)
    }
    
    static func deserializeTemplateData(_ data: Data) -> TemplateData? {
        return try? JSONDecoder().decode(TemplateData.self, from: data)
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("TemplateManager: \(message)")
        #endif
    }
}
