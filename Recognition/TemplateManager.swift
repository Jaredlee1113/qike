import Foundation
import Vision
import UIKit

class TemplateManager {
    struct TemplateData: Codable {
        let featurePrints: [Data]
        let descriptors: [[Float]]
        let ringDescriptors: [[Float]]
        let version: Int
        let createdDate: Date

        enum CodingKeys: String, CodingKey {
            case featurePrints
            case descriptors
            case ringDescriptors
            case version
            case createdDate
        }

        init(
            featurePrints: [VNFeaturePrintObservation],
            descriptors: [[Float]] = [],
            ringDescriptors: [[Float]] = [],
            version: Int = 3,
            createdDate: Date = Date()
        ) {
            self.featurePrints = featurePrints.compactMap { observation in
                try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
            }
            self.descriptors = descriptors
            self.ringDescriptors = ringDescriptors
            self.version = version
            self.createdDate = createdDate
        }

        init(
            featurePrintData: [Data],
            descriptors: [[Float]],
            ringDescriptors: [[Float]],
            version: Int,
            createdDate: Date
        ) {
            self.featurePrints = featurePrintData
            self.descriptors = descriptors
            self.ringDescriptors = ringDescriptors
            self.version = version
            self.createdDate = createdDate
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            featurePrints = try container.decode([Data].self, forKey: .featurePrints)
            descriptors = try container.decodeIfPresent([[Float]].self, forKey: .descriptors) ?? []
            ringDescriptors = try container.decodeIfPresent([[Float]].self, forKey: .ringDescriptors) ?? []
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
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

        func getRingDescriptors() -> [[Float]] {
            ringDescriptors
        }
    }
    
    static func createTemplates(
        from images: [UIImage],
        includeFeaturePrints: Bool = true,
        useCoinDetection: Bool = true
    ) async -> TemplateData {
        var featurePrints: [VNFeaturePrintObservation] = []
        var descriptors: [[Float]] = []
        var ringDescriptors: [[Float]] = []

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
            if let ringDescriptor = ImageProcessor.coinRingDescriptor(for: sourceImage) {
                ringDescriptors.append(ringDescriptor)
            }

            if includeFeaturePrints {
                let processed = ImageProcessor.prepareCoinForMatching(sourceImage)
                if let featurePrint = await generateFeaturePrint(from: processed) {
                    featurePrints.append(featurePrint)
                }
            }
        }

        return TemplateData(
            featurePrints: featurePrints,
            descriptors: descriptors,
            ringDescriptors: ringDescriptors,
            version: 3
        )
    }

    static func createRingDescriptors(
        from images: [UIImage],
        useCoinDetection: Bool = true
    ) async -> [[Float]] {
        var ringDescriptors: [[Float]] = []

        for image in images {
            let normalized = ImageProcessor.normalizeOrientation(image)
            let reduced = ImageProcessor.downscaleImage(normalized, maxDimension: 512)

            let sourceImage: UIImage
            if useCoinDetection, let detected = await CoinDetector.detectSingleCoinFast(from: reduced) {
                sourceImage = detected.maskedImage ?? detected.image
            } else {
                sourceImage = reduced
            }

            if let descriptor = ImageProcessor.coinRingDescriptor(for: sourceImage) {
                ringDescriptors.append(descriptor)
            }
        }

        return ringDescriptors
    }

    static func attachingRingDescriptors(
        to templateData: TemplateData,
        ringDescriptors: [[Float]]
    ) -> TemplateData {
        TemplateData(
            featurePrintData: templateData.featurePrints,
            descriptors: templateData.descriptors,
            ringDescriptors: ringDescriptors,
            version: max(templateData.version, 3),
            createdDate: templateData.createdDate
        )
    }

    static func appendingSamples(
        to templateData: TemplateData,
        images: [UIImage],
        maxSampleCount: Int = 120
    ) async -> TemplateData {
        let sanitizedImages = images.filter { $0.size.width > 8 && $0.size.height > 8 }
        guard !sanitizedImages.isEmpty else { return templateData }

        let learned = await createTemplates(
            from: sanitizedImages,
            includeFeaturePrints: true,
            useCoinDetection: true
        )

        var featurePrints = templateData.featurePrints + learned.featurePrints
        var descriptors = templateData.descriptors + learned.descriptors
        var ringDescriptors = templateData.ringDescriptors + learned.ringDescriptors

        featurePrints = tail(featurePrints, maxCount: maxSampleCount)
        descriptors = tail(descriptors, maxCount: maxSampleCount)
        ringDescriptors = tail(ringDescriptors, maxCount: maxSampleCount)

        return TemplateData(
            featurePrintData: featurePrints,
            descriptors: descriptors,
            ringDescriptors: ringDescriptors,
            version: max(templateData.version, 3),
            createdDate: templateData.createdDate
        )
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

    private static func tail<T>(_ values: [T], maxCount: Int) -> [T] {
        guard maxCount > 0 else { return [] }
        guard values.count > maxCount else { return values }
        return Array(values.suffix(maxCount))
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("TemplateManager: \(message)")
        #endif
    }
}
