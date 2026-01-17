import UIKit
import CoreGraphics

class ROICropper {
    struct Slot {
        let rect: CGRect
        let position: Int
    }
    
    static func extractSlots(from imageSize: CGSize, in viewSize: CGSize) -> [Slot] {
        let slotWidth: CGFloat = 80.0
        let slotHeight: CGFloat = 80.0
        let verticalSpacing: CGFloat = 20.0
        
        let totalHeight = CGFloat(6) * slotHeight + CGFloat(5) * verticalSpacing
        let startY = (viewSize.height - totalHeight) / 2
        let centerX = viewSize.width / 2
        
        var slots: [Slot] = []
        
        for index in 0..<6 {
            let y = startY + CGFloat(index) * (slotHeight + verticalSpacing)
            let x = centerX - slotWidth / 2
            
            let normalizedRect = CGRect(
                x: x / viewSize.width,
                y: y / viewSize.height,
                width: slotWidth / viewSize.width,
                height: slotHeight / viewSize.height
            )
            
            slots.append(Slot(rect: normalizedRect, position: 6 - index))
        }
        
        return slots
    }
    
    static func cropROI(from image: UIImage, slot: Slot) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let cropRect = CGRect(
            x: slot.rect.origin.x * width,
            y: slot.rect.origin.y * height,
            width: slot.rect.size.width * width,
            height: slot.rect.size.height * height
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCGImage)
    }
    
    static func cropAllROIs(from image: UIImage, in viewSize: CGSize) -> [(UIImage, Int)] {
        let slots = extractSlots(from: image.size, in: viewSize)
        
        return slots.compactMap { slot -> (UIImage, Int)? in
            guard let roiImage = cropROI(from: image, slot: slot) else { return nil }
            return (roiImage, slot.position)
        }
    }
}
