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

    private static func mapViewRectToImageRect(
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
        insetRatio: CGFloat = 0.08
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
        insetRatio: CGFloat = 0.08
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
}
