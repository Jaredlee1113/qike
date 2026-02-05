import CoreGraphics

enum SlotLayout {
    struct Slot: Identifiable {
        let id: Int
        let position: Int
        let rect: CGRect
    }

    struct Layout {
        let columnRect: CGRect
        let slots: [Slot]
    }

    static func slots(in size: CGSize) -> [Slot] {
        slotsNormalized(in: size)
    }
    static func slotsNormalized(
        in size: CGSize,
        slotWidthRatio: CGFloat = 0.30,
        spacingRatio: CGFloat = 0.12
    ) -> [Slot] {
        layoutNormalized(in: size, slotWidthRatio: slotWidthRatio, spacingRatio: spacingRatio).slots
    }

    static func columnRectNormalized(
        in size: CGSize,
        slotWidthRatio: CGFloat = 0.30,
        spacingRatio: CGFloat = 0.12
    ) -> CGRect {
        layoutNormalized(in: size, slotWidthRatio: slotWidthRatio, spacingRatio: spacingRatio).columnRect
    }

    static func layoutNormalized(
        in size: CGSize,
        slotWidthRatio: CGFloat = 0.30,
        spacingRatio: CGFloat = 0.12
    ) -> Layout {
        let slotByWidth = size.width * slotWidthRatio
        let slotByHeight = size.height / (CGFloat(6) + CGFloat(5) * spacingRatio)
        let slot = min(slotByWidth, slotByHeight)
        let spacing = slot * spacingRatio
        let totalHeight = CGFloat(6) * slot + CGFloat(5) * spacing
        let startY = (size.height - totalHeight) / 2
        let startX = (size.width - slot) / 2

        let slots = (0..<6).map { index in
            let position = 6 - index
            let y = startY + CGFloat(index) * (slot + spacing)
            let rect = CGRect(x: startX, y: y, width: slot, height: slot)
            return Slot(id: position, position: position, rect: rect)
        }

        let columnRect = CGRect(x: startX, y: startY, width: slot, height: totalHeight)
        return Layout(columnRect: columnRect, slots: slots)
    }
}
