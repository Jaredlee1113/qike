import UIKit
import CoreGraphics

class ROICropper {
    struct Slot {
        let rect: CGRect
        let position: Int
    }

    static func extractSlots(in viewSize: CGSize) -> [Slot] {
        let slots = SlotLayout.slots(in: viewSize)
        return slots.map { Slot(rect: $0.rect, position: $0.position) }
    }
    
    static func cropROI(from image: UIImage, slot: Slot, in viewSize: CGSize) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let cropRect = mapViewRectToImageRect(slot.rect, viewSize: viewSize, imageSize: imageSize)
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCGImage)
    }
    
    static func cropAllROIs(from image: UIImage, in viewSize: CGSize) -> [(UIImage, Int)] {
        let slots = extractSlots(in: viewSize)
        
        return slots.compactMap { slot -> (UIImage, Int)? in
            guard let roiImage = cropROI(from: image, slot: slot, in: viewSize) else { return nil }
            return (roiImage, slot.position)
        }
    }

    static func cropAllROICandidates(
        from image: UIImage,
        in viewSize: CGSize,
        offset: CGFloat = 16
    ) -> [(Int, [UIImage])] {
        let slots = extractSlots(in: viewSize)
        let viewRect = CGRect(origin: .zero, size: viewSize)
        let offsets = [-offset, 0, offset]

        return slots.map { slot in
            var candidates: [UIImage] = []

            for dx in offsets {
                for dy in offsets {
                    let candidateRect = slot.rect.offsetBy(dx: dx, dy: dy)
                    guard viewRect.contains(candidateRect) else { continue }
                    if let image = cropROI(from: image, slot: Slot(rect: candidateRect, position: slot.position), in: viewSize) {
                        candidates.append(image)
                    }
                }
            }

            return (slot.position, candidates)
        }
    }

    static func drafts(from detections: [CoinDetector.DetectedCoin]) -> [DetectionDraft] {
        detections.map { detection in
            DetectionDraft(
                centerNormalized: CGPoint(
                    x: detection.normalizedRect.midX,
                    y: detection.normalizedRect.midY
                ),
                sizeNormalized: detection.normalizedRect.size,
                positionHint: detection.position
            )
        }
    }

    static func defaultDrafts(in imageSize: CGSize) -> [DetectionDraft] {
        let slots = SlotLayout.slotsNormalized(in: imageSize)
        return slots.map { slot in
            DetectionDraft(
                centerNormalized: CGPoint(
                    x: slot.rect.midX / max(imageSize.width, 1),
                    y: slot.rect.midY / max(imageSize.height, 1)
                ),
                sizeNormalized: CGSize(
                    width: slot.rect.width / max(imageSize.width, 1),
                    height: slot.rect.height / max(imageSize.height, 1)
                ),
                positionHint: slot.position
            )
        }
    }

    static func detections(
        from drafts: [DetectionDraft],
        image: UIImage
    ) -> [CoinDetector.DetectedCoin] {
        guard let cgImage = image.cgImage else { return [] }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let bounds = CGRect(origin: .zero, size: imageSize)

        let mapped = drafts.compactMap { draft -> (CGRect, UIImage, UIImage?)? in
            let rect = rectForDraft(draft, imageSize: imageSize).integral.intersection(bounds)
            guard rect.width > 0, rect.height > 0,
                  let cropped = cgImage.cropping(to: rect) else {
                return nil
            }
            let image = UIImage(cgImage: cropped)
            let masked = ImageProcessor.applyCircularMask(image)
            return (rect, image, masked)
        }

        let sorted = Array(mapped.sorted { $0.0.midY < $1.0.midY }.prefix(6))
        return sorted.enumerated().map { index, item in
            let position = 6 - index
            let rect = item.0
            let normalizedRect = CGRect(
                x: rect.origin.x / imageSize.width,
                y: rect.origin.y / imageSize.height,
                width: rect.size.width / imageSize.width,
                height: rect.size.height / imageSize.height
            )
            return CoinDetector.DetectedCoin(
                image: item.1,
                maskedImage: item.2,
                position: position,
                rect: rect,
                normalizedRect: normalizedRect
            )
        }
    }

    static func mapViewRectToImageRect(
        _ viewRect: CGRect,
        viewSize: CGSize,
        imageSize: CGSize
    ) -> CGRect {
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offsetX = (scaledSize.width - viewSize.width) / 2
        let offsetY = (scaledSize.height - viewSize.height) / 2

        let scaledX = viewRect.origin.x + offsetX
        let scaledY = viewRect.origin.y + offsetY
        let originX = scaledX / scale
        let originY = scaledY / scale
        let originWidth = viewRect.size.width / scale
        let originHeight = viewRect.size.height / scale

        let imageRect = CGRect(origin: .zero, size: imageSize)
        return CGRect(x: originX, y: originY, width: originWidth, height: originHeight)
            .intersection(imageRect)
    }

    static func slotDetections(
        for image: UIImage,
        insetRatio: CGFloat = -0.04
    ) -> [CoinDetector.DetectedCoin] {
        guard let cgImage = image.cgImage else { return [] }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let bounds = CGRect(origin: .zero, size: imageSize)
        let slots = SlotLayout.slotsNormalized(in: imageSize)

        return slots.compactMap { slot in
            let inset = min(slot.rect.width, slot.rect.height) * insetRatio
            let rect = slot.rect.insetBy(dx: inset, dy: inset).integral.intersection(bounds)
            guard rect.width > 0, rect.height > 0,
                  let cropped = cgImage.cropping(to: rect) else {
                return nil
            }

            let uiImage = UIImage(cgImage: cropped)
            let masked = ImageProcessor.applyCircularMask(uiImage)
            let normalizedRect = CGRect(
                x: rect.origin.x / imageSize.width,
                y: rect.origin.y / imageSize.height,
                width: rect.size.width / imageSize.width,
                height: rect.size.height / imageSize.height
            )

            return CoinDetector.DetectedCoin(
                image: uiImage,
                maskedImage: masked,
                position: slot.position,
                rect: rect,
                normalizedRect: normalizedRect
            )
        }
    }

    static func slotDetections(
        for image: UIImage,
        in viewSize: CGSize,
        insetRatio: CGFloat = -0.04
    ) -> [CoinDetector.DetectedCoin] {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return slotDetections(for: image, insetRatio: insetRatio)
        }
        guard let cgImage = image.cgImage else { return [] }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let bounds = CGRect(origin: .zero, size: imageSize)
        let slots = SlotLayout.slotsNormalized(in: viewSize)

        return slots.compactMap { slot in
            let inset = min(slot.rect.width, slot.rect.height) * insetRatio
            let viewRect = slot.rect.insetBy(dx: inset, dy: inset).integral
            let rect = mapViewRectToImageRect(viewRect, viewSize: viewSize, imageSize: imageSize)
                .integral
                .intersection(bounds)
            guard rect.width > 0, rect.height > 0,
                  let cropped = cgImage.cropping(to: rect) else {
                return nil
            }

            let uiImage = UIImage(cgImage: cropped)
            let masked = ImageProcessor.applyCircularMask(uiImage)
            let normalizedRect = CGRect(
                x: rect.origin.x / imageSize.width,
                y: rect.origin.y / imageSize.height,
                width: rect.size.width / imageSize.width,
                height: rect.size.height / imageSize.height
            )

            return CoinDetector.DetectedCoin(
                image: uiImage,
                maskedImage: masked,
                position: slot.position,
                rect: rect,
                normalizedRect: normalizedRect
            )
        }
    }

    private static func rectForDraft(
        _ draft: DetectionDraft,
        imageSize: CGSize
    ) -> CGRect {
        let normalizedWidth = min(max(draft.sizeNormalized.width, 0.06), 0.6)
        let normalizedHeight = min(max(draft.sizeNormalized.height, 0.06), 0.6)
        let width = normalizedWidth * imageSize.width
        let height = normalizedHeight * imageSize.height

        var centerX = min(max(draft.centerNormalized.x, 0), 1) * imageSize.width
        var centerY = min(max(draft.centerNormalized.y, 0), 1) * imageSize.height
        centerX = min(max(centerX, width / 2), imageSize.width - width / 2)
        centerY = min(max(centerY, height / 2), imageSize.height - height / 2)

        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }
}
