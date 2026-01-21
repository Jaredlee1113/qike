import CoreGraphics

enum SlotLayout {
    static let slotSize: CGFloat = 100
    static let slotSpacing: CGFloat = 16
    static let labelWidth: CGFloat = 50
    static let labelSpacing: CGFloat = 12

    struct Slot: Identifiable {
        let id: Int
        let position: Int
        let rect: CGRect
    }

    static func slots(in size: CGSize) -> [Slot] {
        let totalHeight = CGFloat(6) * slotSize + CGFloat(5) * slotSpacing
        let startY = (size.height - totalHeight) / 2
        let startX = (size.width - slotSize) / 2

        return (0..<6).map { index in
            let position = 6 - index
            let y = startY + CGFloat(index) * (slotSize + slotSpacing)
            let rect = CGRect(x: startX, y: y, width: slotSize, height: slotSize)
            return Slot(id: position, position: position, rect: rect)
        }
    }

    static func labelCenter(for rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX - labelSpacing - labelWidth / 2,
            y: rect.midY
        )
    }
}
