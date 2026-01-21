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
}
