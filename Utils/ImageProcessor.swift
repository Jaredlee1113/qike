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

    struct CoinQualityCalibration {
        let minEnergy: Float
        let minRingRatio: Float
        let maxCentroidOffset: Float
        let minQualityScore: Float

        static let `default` = CoinQualityCalibration(
            minEnergy: 0.070,
            minRingRatio: 0.055,
            maxCentroidOffset: 0.28,
            minQualityScore: 0.64
        )
    }

    struct CoinPresenceMetrics {
        let energyMean: Float
        let ringRatio: Float
        let centroidOffset: Float
        let qualityScore: Float
        let isPresent: Bool
    }

    static func isCoinPresent(
        energyMean: Float,
        ringRatio: Float,
        calibration: CoinPresenceCalibration = .default
    ) -> Bool {
        let strictPresent = energyMean >= calibration.minEnergy && ringRatio >= calibration.minRingRatio

        // Fallback: some edge slots produce lower ring ratios due perspective/cropping,
        // but still have strong edge energy. Accept these high-confidence cases.
        let relaxedEnergyThreshold = max(calibration.minEnergy * 6, 0.12)
        let relaxedRingThreshold = max(calibration.minRingRatio * 0.35, 0.04)
        let relaxedPresent = energyMean >= relaxedEnergyThreshold && ringRatio >= relaxedRingThreshold

        return strictPresent || relaxedPresent
    }

    static func coinQualityScore(
        energyMean: Float,
        ringRatio: Float,
        centroidOffset: Float
    ) -> Float {
        let energyComponent = min(max(energyMean / 0.2, 0), 1)
        let ringComponent = min(max(ringRatio / 0.12, 0), 1)
        let centerComponent = min(max(1 - (centroidOffset / 0.65), 0), 1)
        return (0.45 * energyComponent) + (0.35 * ringComponent) + (0.20 * centerComponent)
    }

    static func isCoinHighQuality(
        energyMean: Float,
        ringRatio: Float,
        centroidOffset: Float,
        calibration: CoinQualityCalibration = .default
    ) -> Bool {
        let score = coinQualityScore(
            energyMean: energyMean,
            ringRatio: ringRatio,
            centroidOffset: centroidOffset
        )
        return energyMean >= calibration.minEnergy
            && ringRatio >= calibration.minRingRatio
            && centroidOffset <= calibration.maxCentroidOffset
            && score >= calibration.minQualityScore
    }

    static func isCoinHighQualityForSlot(
        position: Int,
        energyMean: Float,
        ringRatio: Float,
        centroidOffset: Float,
        calibration: CoinQualityCalibration = .default
    ) -> Bool {
        if isCoinHighQuality(
            energyMean: energyMean,
            ringRatio: ringRatio,
            centroidOffset: centroidOffset,
            calibration: calibration
        ) {
            return true
        }

        let score = coinQualityScore(
            energyMean: energyMean,
            ringRatio: ringRatio,
            centroidOffset: centroidOffset
        )

        if position == 1 || position == 6 {
            return energyMean >= 0.15
                && ringRatio >= 0.09
                && centroidOffset <= 0.34
                && score >= 0.78
        }

        if position == 2 || position == 5 {
            return energyMean >= 0.13
                && ringRatio >= 0.08
                && centroidOffset <= 0.33
                && score >= 0.74
        }

        return false
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
        var weightedX: Float = 0
        var weightedY: Float = 0
        var weightedSum: Float = 0

        for y in 1..<(height - 1) {
            let row = y * width
            let rowAbove = (y - 1) * width
            let rowBelow = (y + 1) * width
            let fy = Float(y) - cy
            for x in 1..<(width - 1) {
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
                if r <= 0.70 && magnitude > 0 {
                    weightedX += Float(x) * magnitude
                    weightedY += Float(y) * magnitude
                    weightedSum += magnitude
                }
            }
        }

        let count = Float((width - 2) * (height - 2))
        guard totalEnergy > 0, count > 0 else {
            return CoinPresenceMetrics(
                energyMean: 0,
                ringRatio: 0,
                centroidOffset: 1,
                qualityScore: 0,
                isPresent: false
            )
        }

        let energyMean = (totalEnergy / count) / 255.0
        let ringRatio = ringEnergy / totalEnergy
        let centroidOffset: Float
        if weightedSum > 0 {
            let centroidX = weightedX / weightedSum
            let centroidY = weightedY / weightedSum
            let dx = centroidX - cx
            let dy = centroidY - cy
            centroidOffset = sqrt(dx * dx + dy * dy) / radius
        } else {
            centroidOffset = 1
        }
        let qualityScore = coinQualityScore(
            energyMean: energyMean,
            ringRatio: ringRatio,
            centroidOffset: centroidOffset
        )
        let isPresent = isCoinPresent(
            energyMean: energyMean,
            ringRatio: ringRatio,
            calibration: calibration
        )

        return CoinPresenceMetrics(
            energyMean: energyMean,
            ringRatio: ringRatio,
            centroidOffset: centroidOffset,
            qualityScore: qualityScore,
            isPresent: isPresent
        )
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

    static func polarUnwrappedRingImage(
        for image: UIImage,
        innerRadiusRatio: CGFloat = 0.20,
        outerRadiusRatio: CGFloat = 0.48,
        angularSamples: Int = 180,
        radialSamples: Int = 36
    ) -> UIImage? {
        guard let result = polarUnwrapGrayscale(
            for: image,
            innerRadiusRatio: innerRadiusRatio,
            outerRadiusRatio: outerRadiusRatio,
            angularSamples: angularSamples,
            radialSamples: radialSamples
        ) else {
            return nil
        }
        return grayscaleImage(
            from: result.pixels,
            width: result.width,
            height: result.height
        )
    }

    static func coinRingDescriptor(
        for image: UIImage,
        angularSamples: Int = 180,
        radialSamples: Int = 36
    ) -> [Float]? {
        guard let unwrap = polarUnwrapGrayscale(
            for: image,
            innerRadiusRatio: 0.20,
            outerRadiusRatio: 0.48,
            angularSamples: angularSamples,
            radialSamples: radialSamples
        ) else {
            return nil
        }

        let width = unwrap.width
        let height = unwrap.height
        guard width > 8, height > 8 else { return nil }

        var edgeProfile = [Float](repeating: 0, count: width)
        var intensityProfile = [Float](repeating: 0, count: width)

        for x in 0..<width {
            let prevX = (x - 1 + width) % width
            let nextX = (x + 1) % width
            var edgeSum: Float = 0
            var intensitySum: Float = 0

            for y in 0..<height {
                let idx = y * width + x
                intensitySum += unwrap.pixels[idx]

                let left = unwrap.pixels[y * width + prevX]
                let right = unwrap.pixels[y * width + nextX]
                edgeSum += abs(right - left)
            }

            intensityProfile[x] = intensitySum / Float(height)
            edgeProfile[x] = edgeSum / Float(height)
        }

        let normalizedEdge = normalizedProfile(edgeProfile)
        let normalizedIntensity = normalizedProfile(intensityProfile)
        guard !normalizedEdge.isEmpty, !normalizedIntensity.isEmpty else { return nil }
        return normalizedEdge + normalizedIntensity
    }

    private static func polarUnwrapGrayscale(
        for image: UIImage,
        innerRadiusRatio: CGFloat,
        outerRadiusRatio: CGFloat,
        angularSamples: Int,
        radialSamples: Int
    ) -> (pixels: [Float], width: Int, height: Int)? {
        guard angularSamples > 16, radialSamples > 8 else { return nil }

        let normalized = normalizeOrientation(image)
        let squared = centerCropToSquare(normalized)
        let resized = resizeImage(squared, targetSize: CGSize(width: 256, height: 256))
        guard let cgImage = resized.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 8, height > 8 else { return nil }

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

        let cx = CGFloat(width - 1) / 2
        let cy = CGFloat(height - 1) / 2
        let maxRadius = min(cx, cy)

        let clampedInner = min(max(innerRadiusRatio, 0.05), 0.75)
        let clampedOuter = min(max(outerRadiusRatio, clampedInner + 0.08), 0.98)
        let innerRadius = maxRadius * clampedInner
        let outerRadius = maxRadius * clampedOuter
        let radiusDelta = max(outerRadius - innerRadius, 1)

        var unwrapped = [Float](repeating: 0, count: angularSamples * radialSamples)
        let twoPi = CGFloat.pi * 2

        for y in 0..<radialSamples {
            let t = (CGFloat(y) + 0.5) / CGFloat(radialSamples)
            let radius = innerRadius + (radiusDelta * t)

            for x in 0..<angularSamples {
                let theta = twoPi * (CGFloat(x) / CGFloat(angularSamples))
                let sx = cx + radius * cos(theta)
                let sy = cy + radius * sin(theta)
                unwrapped[y * angularSamples + x] = bilinearSample(
                    gray,
                    width: width,
                    height: height,
                    x: sx,
                    y: sy
                ) / 255.0
            }
        }

        return (unwrapped, angularSamples, radialSamples)
    }

    private static func bilinearSample(
        _ pixels: [UInt8],
        width: Int,
        height: Int,
        x: CGFloat,
        y: CGFloat
    ) -> Float {
        let clampedX = min(max(x, 0), CGFloat(width - 1))
        let clampedY = min(max(y, 0), CGFloat(height - 1))

        let x0 = Int(floor(clampedX))
        let y0 = Int(floor(clampedY))
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)

        let dx = Float(clampedX - CGFloat(x0))
        let dy = Float(clampedY - CGFloat(y0))

        let p00 = Float(pixels[y0 * width + x0])
        let p10 = Float(pixels[y0 * width + x1])
        let p01 = Float(pixels[y1 * width + x0])
        let p11 = Float(pixels[y1 * width + x1])

        let top = p00 * (1 - dx) + p10 * dx
        let bottom = p01 * (1 - dx) + p11 * dx
        return top * (1 - dy) + bottom * dy
    }

    private static func normalizedProfile(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return [] }
        let mean = values.reduce(0, +) / Float(values.count)
        var centered = values.map { $0 - mean }

        var norm: Float = 0
        for value in centered {
            norm += value * value
        }
        norm = sqrt(max(norm, 1e-6))
        guard norm > 0 else { return [] }

        for index in centered.indices {
            centered[index] /= norm
        }
        return centered
    }

    private static func grayscaleImage(
        from normalizedPixels: [Float],
        width: Int,
        height: Int
    ) -> UIImage? {
        guard width > 0, height > 0, normalizedPixels.count == width * height else { return nil }
        let bytes = normalizedPixels.map { value -> UInt8 in
            let clamped = min(max(value, 0), 1)
            return UInt8(clamped * 255)
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
