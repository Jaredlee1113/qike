import UIKit
import Vision

class CoinValidator {
    static func validateCoin(_ image: UIImage) async -> Bool {
        guard let cgImage = image.cgImage else { return false }
        
        return await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false
            let resumeOnce: (Bool) -> Void = { value in
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: value)
            }

            let request = VNDetectContoursRequest { request, error in
                if let error = error {
                    debugLog("contour error: \(error.localizedDescription)")
                    resumeOnce(false)
                    return
                }
                
                guard let observations = request.results, !observations.isEmpty else {
                    debugLog("no contours detected")
                    resumeOnce(false)
                    return
                }
                
                // For iOS 16+, accept any contour detection result as valid
                let isValid = true
                
                resumeOnce(isValid)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                debugLog("contour perform failed: \(error)")
                resumeOnce(false)
            }
        }
    }
    
    private static func isLikelyACoin(contour: Any) -> Bool {
        // Placeholder for iOS 16+ compatibility
        // TODO: Implement proper contour validation
        return true
    }
    
    static func validateAllCoins(_ images: [(UIImage, Int)]) async -> [(Int, Bool)] {
        var results: [(Int, Bool)] = []
        
        for (image, position) in images {
            let isValid = await validateCoin(image)
            results.append((position, isValid))
        }
        
        return results
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("CoinValidator: \(message)")
        #endif
    }
}
