import UIKit
import Vision
import CoreImage

class ImageProcessor {
    private static let colorContext = CIContext()

    struct CoinPresenceCalibration {
        let minEnergy: Float
        let minRingRatio: Float

        static let `default` = CoinPresenceCalibration(minEnergy: 0.02, minRingRatio: 0.12)
    }

    struct CoinPresenceMetrics {
        let energyMean: Float
        let ringRatio: Float
        let isPresent: Bool
    }

    static func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? image
    }

    static func centerCropToSquare(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let side = min(width, height)
        let originX = (width - side) / 2
        let originY = (height - side) / 2
        let rect = CGRect(x: originX, y: originY, width: side, height: side)

        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
    }

    static func centerCrop(_ image: UIImage, scale: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let clampedScale = min(max(scale, 0.3), 1.0)
        let side = min(width, height) * clampedScale
        let originX = (width - side) / 2
        let originY = (height - side) / 2
        let rect = CGRect(x: originX, y: originY, width: side, height: side)

        guard let cropped = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped)
    }

    static func zoomedVariants(for image: UIImage, scales: [CGFloat]) -> [UIImage] {
        let uniqueScales = Array(Set(scales)).sorted(by: >)
        return uniqueScales.map { scale in
            if abs(scale - 1.0) < 0.001 {
                return image
            }
            return centerCrop(image, scale: scale)
        }
    }

    static func prepareForMatching(_ image: UIImage, targetSize: CGSize = CGSize(width: 299, height: 299)) -> UIImage {
        let normalized = normalizeOrientation(image)
        let squared = centerCropToSquare(normalized)
        return resizeImage(squared, targetSize: targetSize)
    }

    static func prepareCoinForMatching(_ image: UIImage, targetSize: CGSize = CGSize(width: 299, height: 299)) -> UIImage {
        let normalized = normalizeOrientation(image)
        let squared = centerCropToSquare(normalized)
        let masked = applyCircularMask(squared)
        let resized = resizeImage(masked, targetSize: targetSize)
        return applyColorControls(resized, contrast: 1.1, brightness: 0.02, saturation: 0.0)
    }

    static func cropROI(from image: UIImage, rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let scaledRect = CGRect(
            x: rect.origin.x * CGFloat(cgImage.width),
            y: rect.origin.y * CGFloat(cgImage.height),
            width: rect.size.width * CGFloat(cgImage.width),
            height: rect.size.height * CGFloat(cgImage.height)
        )
        
        guard let croppedCGImage = cgImage.cropping(to: scaledRect) else { return nil }
        return UIImage(cgImage: croppedCGImage)
    }
    
    static func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        var newSize: CGSize
        if widthRatio > heightRatio {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
        }
        
        let rect = CGRect(origin: .zero, size: newSize)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }

    static func downscaleImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        guard maxDimension > 0 else { return image }
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return scaled ?? image
    }
    
    static func preprocessForVision(_ image: UIImage) -> UIImage {
        return resizeImage(image, targetSize: CGSize(width: 299, height: 299))
    }

    static func applyColorControls(
        _ image: UIImage,
        contrast: CGFloat,
        brightness: CGFloat,
        saturation: CGFloat = 0.0
    ) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(saturation, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage,
              let cgOutput = colorContext.createCGImage(output, from: output.extent) else {
            return image
        }
        return UIImage(cgImage: cgOutput)
    }

    static func applyCircularMask(_ image: UIImage, insetRatio: CGFloat = 0.06) -> UIImage {
        let size = image.size
        let minSide = min(size.width, size.height)
        let inset = minSide * insetRatio
        let radius = max((minSide - inset * 2) / 2, 1)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let circleRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.addEllipse(in: circleRect)
        context.clip()
        image.draw(in: CGRect(origin: .zero, size: size))
        let masked = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return masked ?? image
    }

    static func imageFromPixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        context: CIContext = CIContext()
    ) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let rect = ciImage.extent
        guard let cgImage = context.createCGImage(ciImage, from: rect) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func coinPresenceMetrics(
        for image: UIImage,
        size: Int = 96,
        calibration: CoinPresenceCalibration = .default
    ) -> CoinPresenceMetrics? {
        let normalized = normalizeOrientation(image)
        let squared = centerCropToSquare(normalized)
        let resized = resizeImage(squared, targetSize: CGSize(width: size, height: size))
        guard let cgImage = resized.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 2, height > 2 else { return nil }

        let bytesPerRow = width
        var gray = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &gray,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let cx = Float(width - 1) / 2
        let cy = Float(height - 1) / 2
        let radius = max(min(cx, cy), 1)

        var totalEnergy: Float = 0
        var ringEnergy: Float = 0

        for y in 1..<(height - 1) {
            let row = y * width
            let rowAbove = (y - 1) * width
            let rowBelow = (y + 1) * width
            let fy = Float(y) - cy
            for x in 1..<(width - 1) {
                let idx = row + x
                let fx = Float(x) - cx

                let gx =
                    -1 * Int(gray[rowAbove + x - 1]) + 1 * Int(gray[rowAbove + x + 1]) +
                    -2 * Int(gray[row + x - 1])     + 2 * Int(gray[row + x + 1]) +
                    -1 * Int(gray[rowBelow + x - 1]) + 1 * Int(gray[rowBelow + x + 1])

                let gy =
                    -1 * Int(gray[rowAbove + x - 1]) + -2 * Int(gray[rowAbove + x]) + -1 * Int(gray[rowAbove + x + 1]) +
                     1 * Int(gray[rowBelow + x - 1]) +  2 * Int(gray[rowBelow + x]) +  1 * Int(gray[rowBelow + x + 1])

                let magnitude = sqrt(Float(gx * gx + gy * gy))
                totalEnergy += magnitude

                let r = sqrt(fx * fx + fy * fy) / radius
                if r >= 0.32 && r <= 0.50 {
                    ringEnergy += magnitude
                }
            }
        }

        let count = Float((width - 2) * (height - 2))
        guard totalEnergy > 0, count > 0 else {
            return CoinPresenceMetrics(energyMean: 0, ringRatio: 0, isPresent: false)
        }

        let energyMean = (totalEnergy / count) / 255.0
        let ringRatio = ringEnergy / totalEnergy
        let isPresent = energyMean >= calibration.minEnergy && ringRatio >= calibration.minRingRatio

        return CoinPresenceMetrics(energyMean: energyMean, ringRatio: ringRatio, isPresent: isPresent)
    }

    static func coinDescriptor(for image: UIImage, size: Int = 64) -> [Float]? {
        let targetSize = CGSize(width: size, height: size)
        let prepared = prepareCoinForMatching(image, targetSize: targetSize)
        guard let cgImage = prepared.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 2, height > 2 else { return nil }

        let bytesPerRow = width
        var gray = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &gray,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var features = [Float](repeating: 0, count: width * height)

        for y in 1..<(height - 1) {
            let row = y * width
            let rowAbove = (y - 1) * width
            let rowBelow = (y + 1) * width
            for x in 1..<(width - 1) {
                let idx = row + x
                let gx =
                    -1 * Int(gray[rowAbove + x - 1]) + 1 * Int(gray[rowAbove + x + 1]) +
                    -2 * Int(gray[row + x - 1])     + 2 * Int(gray[row + x + 1]) +
                    -1 * Int(gray[rowBelow + x - 1]) + 1 * Int(gray[rowBelow + x + 1])

                let gy =
                    -1 * Int(gray[rowAbove + x - 1]) + -2 * Int(gray[rowAbove + x]) + -1 * Int(gray[rowAbove + x + 1]) +
                     1 * Int(gray[rowBelow + x - 1]) +  2 * Int(gray[rowBelow + x]) +  1 * Int(gray[rowBelow + x + 1])

                let magnitude = sqrt(Float(gx * gx + gy * gy))
                features[idx] = magnitude
            }
        }

        var sumSquares: Float = 0
        for value in features {
            sumSquares += value * value
        }
        let norm = sqrt(max(sumSquares, 1e-6))
        for i in 0..<features.count {
            features[i] /= norm
        }

        return features
    }

    static func rotatedVariants(for image: UIImage) -> [UIImage] {
        guard let cgImage = image.cgImage else { return [image] }
        return [
            image,
            UIImage(cgImage: cgImage, scale: image.scale, orientation: .right),
            UIImage(cgImage: cgImage, scale: image.scale, orientation: .down),
            UIImage(cgImage: cgImage, scale: image.scale, orientation: .left)
        ]
    }
}
