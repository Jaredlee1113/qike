import Vision
import UIKit

class CoinDetector {
    private struct Candidate {
        let rect: CGRect
        let area: CGFloat
        let normalizedPath: CGPath
        let hasValidHole: Bool
    }

    struct DetectedCoin {
        let image: UIImage
        let maskedImage: UIImage?
        let position: Int
        let rect: CGRect
        let normalizedRect: CGRect
    }

    static func detectCoins(from image: UIImage) async -> [DetectedCoin] {
        guard let baseCGImage = image.cgImage else { return [] }
        let imageSize = CGSize(width: baseCGImage.width, height: baseCGImage.height)

        var holeCandidatePool: [Candidate] = []

        let firstContours = await detectContours(in: baseCGImage, detectsDarkOnLight: true, contrast: 1.0)
        holeCandidatePool.append(contentsOf: holeDerivedCandidates(from: firstContours, imageSize: imageSize, allowStandaloneHoles: false))

        if holeCandidatePool.count < 6 {
            let secondContours = await detectContours(in: baseCGImage, detectsDarkOnLight: false, contrast: 1.0)
            holeCandidatePool.append(contentsOf: holeDerivedCandidates(from: secondContours, imageSize: imageSize, allowStandaloneHoles: false))
        }

        if holeCandidatePool.count < 6, let enhanced = enhanceContrast(for: baseCGImage) {
            let enhancedContours = await detectContours(in: enhanced, detectsDarkOnLight: true, contrast: 1.3)
            holeCandidatePool.append(contentsOf: holeDerivedCandidates(from: enhancedContours, imageSize: imageSize, allowStandaloneHoles: false))
        }

        if holeCandidatePool.count < 6 {
            holeCandidatePool.append(contentsOf: holeDerivedCandidates(from: firstContours, imageSize: imageSize, allowStandaloneHoles: true))
        }

        let holeCandidates = dedupeCandidates(holeCandidatePool)
        debugLog("hole candidates: \(holeCandidates.count)")

        guard holeCandidates.count >= 6 else {
            debugLog("not enough hole candidates: \(holeCandidates.count)")
            return []
        }

        let selected = selectBestSixCandidates(from: holeCandidates)
        guard selected.count >= 6 else {
            debugLog("not enough selected candidates: \(selected.count)")
            return []
        }

        let paddedCandidates = selected.map { candidate -> (Candidate, CGRect) in
            (candidate, padRect(candidate.rect, in: imageSize))
        }
        let sortedCandidates = paddedCandidates.sorted { $0.1.midY < $1.1.midY }

        var results: [DetectedCoin] = []
        for (index, item) in sortedCandidates.enumerated() {
            let candidate = item.0
            let rect = item.1
            guard let rawCrop = baseCGImage.cropping(to: rect) else { continue }
            let masked = maskCoin(in: baseCGImage, rect: rect, normalizedPath: candidate.normalizedPath, imageSize: imageSize)
            let position = 6 - index
            let normalizedRect = CGRect(
                x: rect.origin.x / imageSize.width,
                y: rect.origin.y / imageSize.height,
                width: rect.size.width / imageSize.width,
                height: rect.size.height / imageSize.height
            )
            results.append(DetectedCoin(
                image: UIImage(cgImage: rawCrop),
                maskedImage: masked.map { UIImage(cgImage: $0) },
                position: position,
                rect: rect,
                normalizedRect: normalizedRect
            ))
        }

        debugLog("coins detected: \(results.count)")
        return results
    }

    private static func candidates(
        from contours: [VNContour],
        imageSize: CGSize,
        requireHole: Bool,
        minimumAreaRatio: CGFloat
    ) -> [Candidate] {
        var candidates: [Candidate] = []

        for contour in contours {
            let normalizedRect = contour.normalizedPath.boundingBox

            let holeRect = largestChildRect(for: contour)
            let hasValidHole = holeRect.map { isValidHole($0, outerRect: normalizedRect) } ?? false
            if requireHole && !hasValidHole {
                continue
            }

            let rect = imageRect(from: normalizedRect, imageSize: imageSize)
            let area = rect.width * rect.height
            let areaRatio = area / (imageSize.width * imageSize.height)
            let aspectRatio = rect.width / max(rect.height, 1)

            guard aspectRatio > 0.6, aspectRatio < 1.4 else { continue }
            guard areaRatio > minimumAreaRatio, areaRatio < 0.2 else { continue }

            candidates.append(Candidate(rect: rect, area: area, normalizedPath: contour.normalizedPath, hasValidHole: hasValidHole))
        }

        return candidates
    }

    private static func holeDerivedCandidates(
        from contours: [VNContour],
        imageSize: CGSize,
        allowStandaloneHoles: Bool
    ) -> [Candidate] {
        var candidates: [Candidate] = []

        for contour in contours {
            let outerRect = contour.normalizedPath.boundingBox

            for child in contour.childContours {
                let holeRect = child.normalizedPath.boundingBox
                guard isValidHole(holeRect, outerRect: outerRect) else { continue }
                let scale = scaleFromOuter(outerRect: outerRect, holeRect: holeRect)
                if let derived = derivedRect(from: holeRect, scale: scale) {
                    if let candidate = candidateFromNormalizedRect(
                        derived,
                        imageSize: imageSize,
                        hasValidHole: true
                    ) {
                        candidates.append(candidate)
                    }
                }
            }

            if allowStandaloneHoles {
                let holeRect = outerRect
                guard isStandaloneHole(holeRect) else { continue }
                if let derived = derivedRect(from: holeRect, scale: 3.4) {
                    if let candidate = candidateFromNormalizedRect(
                        derived,
                        imageSize: imageSize,
                        hasValidHole: true
                    ) {
                        candidates.append(candidate)
                    }
                }
            }
        }

        return candidates
    }

    private static func selectHoleCandidates(from candidates: [Candidate]) -> [Candidate] {
        guard candidates.count > 6 else { return candidates }

        let sizes = candidates.map { min($0.rect.width, $0.rect.height) }
        let medianSize = median(sizes)

        let sortedByArea = candidates.sorted { $0.area > $1.area }
        var kept: [Candidate] = []

        for candidate in sortedByArea {
            if isDuplicate(candidate, kept, minDistance: medianSize * 0.6, iouThreshold: 0.4) {
                continue
            }
            kept.append(candidate)
        }

        if kept.count < 6 {
            kept = Array(sortedByArea.prefix(6))
        } else if kept.count > 6 {
            let (slope, intercept) = fitLineXoverY(kept)
            let scored = kept.map { candidate -> (Candidate, CGFloat) in
                let center = CGPoint(x: candidate.rect.midX, y: candidate.rect.midY)
                let predictedX = slope * center.y + intercept
                return (candidate, abs(center.x - predictedX))
            }
            kept = Array(scored.sorted { $0.1 < $1.1 }.prefix(6).map { $0.0 })
        }

        return kept
    }

    private static func scaleFromOuter(outerRect: CGRect, holeRect: CGRect) -> CGFloat {
        let outerArea = outerRect.width * outerRect.height
        let holeArea = holeRect.width * holeRect.height
        guard outerArea > 0, holeArea > 0 else { return 3.4 }
        let ratio = sqrt(outerArea / holeArea)
        return min(max(ratio, 2.6), 4.8)
    }

    private static func derivedRect(from holeRect: CGRect, scale: CGFloat) -> CGRect? {
        guard scale > 0 else { return nil }
        let holeSize = max(holeRect.width, holeRect.height)
        let size = holeSize * scale
        let center = CGPoint(x: holeRect.midX, y: holeRect.midY)
        let origin = CGPoint(x: center.x - size / 2, y: center.y - size / 2)
        let derived = CGRect(origin: origin, size: CGSize(width: size, height: size))
        return clampNormalizedRect(derived)
    }

    private static func clampNormalizedRect(_ rect: CGRect) -> CGRect? {
        let x = max(0, rect.origin.x)
        let y = max(0, rect.origin.y)
        let maxWidth = 1.0 - x
        let maxHeight = 1.0 - y
        let width = min(rect.width, maxWidth)
        let height = min(rect.height, maxHeight)
        guard width > 0, height > 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func candidateFromNormalizedRect(
        _ normalizedRect: CGRect,
        imageSize: CGSize,
        hasValidHole: Bool
    ) -> Candidate? {
        let rect = imageRect(from: normalizedRect, imageSize: imageSize)
        let area = rect.width * rect.height
        let areaRatio = area / (imageSize.width * imageSize.height)
        let aspectRatio = rect.width / max(rect.height, 1)

        guard aspectRatio > 0.6, aspectRatio < 1.4 else { return nil }
        guard areaRatio > 0.002, areaRatio < 0.2 else { return nil }

        let path = CGPath(rect: normalizedRect, transform: nil)
        return Candidate(rect: rect, area: area, normalizedPath: path, hasValidHole: hasValidHole)
    }

    private static func largestChildRect(for contour: VNContour) -> CGRect? {
        guard !contour.childContours.isEmpty else { return nil }
        var bestRect: CGRect?
        var maxArea: CGFloat = 0

        for child in contour.childContours {
            let rect = child.normalizedPath.boundingBox
            let area = rect.width * rect.height
            if area > maxArea {
                maxArea = area
                bestRect = rect
            }
        }

        return bestRect
    }

    private static func isStandaloneHole(_ holeRect: CGRect) -> Bool {
        let area = holeRect.width * holeRect.height
        guard area > 0 else { return false }
        let aspect = holeRect.width / max(holeRect.height, 1e-6)
        guard aspect > 0.7, aspect < 1.3 else { return false }
        return area > 0.00005 && area < 0.005
    }
    private static func isValidHole(_ holeRect: CGRect, outerRect: CGRect) -> Bool {
        guard outerRect.width > 0, outerRect.height > 0 else { return false }
        let holeAreaRatio = (holeRect.width * holeRect.height) / (outerRect.width * outerRect.height)
        guard holeAreaRatio > 0.04, holeAreaRatio < 0.35 else { return false }

        let holeAspect = holeRect.width / max(holeRect.height, 1e-6)
        guard holeAspect > 0.5, holeAspect < 1.5 else { return false }

        let outerCenter = CGPoint(x: outerRect.midX, y: outerRect.midY)
        let holeCenter = CGPoint(x: holeRect.midX, y: holeRect.midY)
        let maxOffset = 0.2 * min(outerRect.width, outerRect.height)

        return abs(holeCenter.x - outerCenter.x) <= maxOffset
            && abs(holeCenter.y - outerCenter.y) <= maxOffset
    }

    private static func selectBestSixCandidates(from candidates: [Candidate]) -> [Candidate] {
        guard candidates.count > 6 else { return candidates }

        let medianArea = median(candidates.map(\.area))
        var trimmed = candidates.sorted {
            abs($0.area - medianArea) < abs($1.area - medianArea)
        }
        if trimmed.count > 14 {
            trimmed = Array(trimmed.prefix(14))
        }

        let stats = trimmed.map { candidate -> (Candidate, CGPoint, CGFloat) in
            let center = CGPoint(x: candidate.rect.midX, y: candidate.rect.midY)
            let size = min(candidate.rect.width, candidate.rect.height)
            return (candidate, center, size)
        }

        var bestScore = -Double.greatestFiniteMagnitude
        var bestSet: [Candidate] = []

        var indices: [Int] = []
        func evaluateCombination(_ combo: [Int]) {
            var points: [CGPoint] = []
            var sizes: [CGFloat] = []
            points.reserveCapacity(6)
            sizes.reserveCapacity(6)

            for index in combo {
                points.append(stats[index].1)
                sizes.append(stats[index].2)
            }

            let meanSize = average(sizes)
            guard meanSize > 0 else { return }

            let (slope, intercept) = fitLineXoverY(points)
            var lineResiduals: [CGFloat] = []
            lineResiduals.reserveCapacity(6)
            for point in points {
                let predictedX = slope * point.y + intercept
                lineResiduals.append(abs(point.x - predictedX))
            }
            let lineDeviation = average(lineResiduals) / meanSize

            let sortedByY = points.sorted { $0.y < $1.y }
            var spacings: [CGFloat] = []
            spacings.reserveCapacity(5)
            for i in 1..<sortedByY.count {
                spacings.append(sortedByY[i].y - sortedByY[i - 1].y)
            }
            let meanSpacing = average(spacings)
            let spacingStd = standardDeviation(spacings, mean: meanSpacing)
            let spacingScore = spacingStd / max(meanSpacing, meanSize)

            let sizeStd = standardDeviation(sizes, mean: meanSize) / meanSize

            let xs = points.map(\.x)
            let xSpread = (xs.max() ?? 0) - (xs.min() ?? 0)
            let xSpreadScore = xSpread / meanSize

            let cost = (lineDeviation * 2.0) + (spacingScore * 1.4) + (sizeStd * 1.0) + (xSpreadScore * 1.4)
            let score = -Double(cost)

            if score > bestScore {
                bestScore = score
                bestSet = combo.map { stats[$0].0 }
            }
        }

        func combine(_ start: Int, _ remaining: Int) {
            if remaining == 0 {
                evaluateCombination(indices)
                return
            }
            guard start < stats.count else { return }
            for i in start..<(stats.count - remaining + 1) {
                indices.append(i)
                combine(i + 1, remaining - 1)
                indices.removeLast()
            }
        }

        combine(0, 6)
        return bestSet
    }

    private static func fitLineXoverY(_ candidates: [Candidate]) -> (CGFloat, CGFloat) {
        let points = candidates.map { CGPoint(x: $0.rect.midX, y: $0.rect.midY) }
        let meanY = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        let meanX = points.map(\.x).reduce(0, +) / CGFloat(points.count)

        var numerator: CGFloat = 0
        var denominator: CGFloat = 0

        for point in points {
            let dy = point.y - meanY
            numerator += dy * (point.x - meanX)
            denominator += dy * dy
        }

        guard denominator != 0 else {
            return (0, meanX)
        }

        let slope = numerator / denominator
        let intercept = meanX - slope * meanY
        return (slope, intercept)
    }

    private static func fitLineXoverY(_ points: [CGPoint]) -> (CGFloat, CGFloat) {
        guard !points.isEmpty else { return (0, 0) }
        let meanY = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        let meanX = points.map(\.x).reduce(0, +) / CGFloat(points.count)

        var numerator: CGFloat = 0
        var denominator: CGFloat = 0

        for point in points {
            let dy = point.y - meanY
            numerator += dy * (point.x - meanX)
            denominator += dy * dy
        }

        guard denominator != 0 else {
            return (0, meanX)
        }

        let slope = numerator / denominator
        let intercept = meanX - slope * meanY
        return (slope, intercept)
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func average(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / CGFloat(values.count)
    }

    private static func standardDeviation(_ values: [CGFloat], mean: CGFloat) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / CGFloat(values.count)
        return sqrt(variance)
    }

    private static func isDuplicate(
        _ candidate: Candidate,
        _ kept: [Candidate],
        minDistance: CGFloat,
        iouThreshold: CGFloat
    ) -> Bool {
        let center = CGPoint(x: candidate.rect.midX, y: candidate.rect.midY)

        for other in kept {
            let otherCenter = CGPoint(x: other.rect.midX, y: other.rect.midY)
            let distance = hypot(center.x - otherCenter.x, center.y - otherCenter.y)
            if distance < minDistance {
                return true
            }

            let iou = intersectionOverUnion(candidate.rect, other.rect)
            if iou > iouThreshold {
                return true
            }
        }

        return false
    }

    private static func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private static func detectContours(
        in cgImage: CGImage,
        detectsDarkOnLight: Bool,
        contrast: Float
    ) async -> [VNContour] {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false
            let resumeOnce: ([VNContour]) -> Void = { value in
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: value)
            }

            let request = VNDetectContoursRequest { request, error in
                if let error = error {
                    debugLog("contour error: \(error.localizedDescription)")
                    resumeOnce([])
                    return
                }

                guard let observation = request.results?.first as? VNContoursObservation else {
                    debugLog("contour observation missing")
                    resumeOnce([])
                    return
                }

                let topContours = observation.topLevelContours
                if !topContours.isEmpty {
                    resumeOnce(topContours)
                    return
                }

                var contours: [VNContour] = []
                for index in 0..<observation.contourCount {
                    if let contour = try? observation.contour(at: index) {
                        contours.append(contour)
                    }
                }

                resumeOnce(contours)
            }

            request.detectsDarkOnLight = detectsDarkOnLight
            request.contrastAdjustment = contrast
            request.maximumImageDimension = 640

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                debugLog("contour perform failed: \(error)")
                resumeOnce([])
            }
        }
    }

    private static func imageRect(from normalizedRect: CGRect, imageSize: CGSize) -> CGRect {
        let rect = VNImageRectForNormalizedRect(
            normalizedRect,
            Int(imageSize.width),
            Int(imageSize.height)
        )
        let flippedY = imageSize.height - rect.origin.y - rect.size.height
        return CGRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
    }

    private static func padRect(_ rect: CGRect, in imageSize: CGSize) -> CGRect {
        let paddingFactor: CGFloat = 0.3
        let size = max(rect.width, rect.height) * (1 + paddingFactor)
        let originX = rect.midX - size / 2
        let originY = rect.midY - size / 2
        let padded = CGRect(x: originX, y: originY, width: size, height: size)
        let bounds = CGRect(origin: .zero, size: imageSize)
        return padded.intersection(bounds)
    }

    private static func dedupeCandidates(_ candidates: [Candidate]) -> [Candidate] {
        let sorted = candidates.sorted { $0.area > $1.area }
        var unique: [Candidate] = []

        for candidate in sorted {
            if unique.contains(where: { isDuplicate(candidate, $0) }) {
                continue
            }
            unique.append(candidate)
        }

        return unique
    }

    private static func isDuplicate(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        let dx = lhs.rect.midX - rhs.rect.midX
        let dy = lhs.rect.midY - rhs.rect.midY
        let distance = hypot(dx, dy)
        let threshold = min(lhs.rect.width, lhs.rect.height) * 0.3
        return distance < threshold
    }

    private static func maskCoin(
        in cgImage: CGImage,
        rect: CGRect,
        normalizedPath: CGPath,
        imageSize: CGSize
    ) -> CGImage? {
        guard let cropped = cgImage.cropping(to: rect) else { return nil }

        let size = rect.size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return cropped }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let pathInImage = transformPathToImage(normalizedPath, imageSize: imageSize)
        var translation = CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y)
        let offsetPath = pathInImage.copy(using: &translation)

        if let offsetPath = offsetPath {
            context.addPath(offsetPath)
            context.clip()
        }

        context.draw(cropped, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    private static func transformPathToImage(_ path: CGPath, imageSize: CGSize) -> CGPath {
        var transform = CGAffineTransform(scaleX: imageSize.width, y: imageSize.height)
        let scaled = path.copy(using: &transform) ?? path

        var flip = CGAffineTransform(scaleX: 1, y: -1)
        flip = flip.translatedBy(x: 0, y: -imageSize.height)
        return scaled.copy(using: &flip) ?? scaled
    }

    private static func enhanceContrast(for cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(1.6, forKey: kCIInputContrastKey)
        filter.setValue(0.05, forKey: kCIInputBrightnessKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)

        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        return context.createCGImage(output, from: output.extent)
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("CoinDetector: \(message)")
        #endif
    }
}
