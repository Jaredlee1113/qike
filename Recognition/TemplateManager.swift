import Foundation
import Vision
import UIKit

class TemplateManager {
    struct TemplateData: Codable {
        let featurePrints: [Data]
        let createdDate: Date
        
        init(featurePrints: [VNFeaturePrintObservation]) {
            self.featurePrints = featurePrints.compactMap { observation in
                try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
            }
            self.createdDate = Date()
        }
        
        func getObservations() -> [VNFeaturePrintObservation] {
            return featurePrints.compactMap { data in
                try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
            }
        }
    }
    
    static func createTemplates(from images: [UIImage]) async -> TemplateData {
        var featurePrints: [VNFeaturePrintObservation] = []
        
        for image in images {
            let processed = ImageProcessor.prepareForMatching(image)
            if let featurePrint = await generateFeaturePrint(from: processed) {
                featurePrints.append(featurePrint)
            }
        }
        
        return TemplateData(featurePrints: featurePrints)
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
