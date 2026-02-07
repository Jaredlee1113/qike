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
        spacingRatio: CGFloat = 0.12,
        verticalInsetRatio: CGFloat = 0.08
    ) -> [Slot] {
        layoutNormalized(
            in: size,
            slotWidthRatio: slotWidthRatio,
            spacingRatio: spacingRatio,
            verticalInsetRatio: verticalInsetRatio
        ).slots
    }

    static func columnRectNormalized(
        in size: CGSize,
        slotWidthRatio: CGFloat = 0.30,
        spacingRatio: CGFloat = 0.12,
        verticalInsetRatio: CGFloat = 0.08
    ) -> CGRect {
        layoutNormalized(
            in: size,
            slotWidthRatio: slotWidthRatio,
            spacingRatio: spacingRatio,
            verticalInsetRatio: verticalInsetRatio
        ).columnRect
    }

    static func layoutNormalized(
        in size: CGSize,
        slotWidthRatio: CGFloat = 0.30,
        spacingRatio: CGFloat = 0.12,
        verticalInsetRatio: CGFloat = 0.08
    ) -> Layout {
        guard size.width > 0, size.height > 0 else {
            return Layout(columnRect: .zero, slots: [])
        }

        let clampedInsetRatio = min(max(verticalInsetRatio, 0), 0.2)
        let usableHeight = size.height * (1 - 2 * clampedInsetRatio)
        let preferredSlotByWidth = size.width * slotWidthRatio
        let slotByHeightWithSpacing = usableHeight / (CGFloat(6) + CGFloat(5) * spacingRatio)
        let slot = max(1, min(preferredSlotByWidth, slotByHeightWithSpacing))
        let usedHeight = CGFloat(6) * slot
        let topBottomInset = size.height * clampedInsetRatio
        let remainingHeight = max(usableHeight - usedHeight, 0)
        let spacing = remainingHeight / CGFloat(5)
        let startX = (size.width - slot) / 2
        let startY = topBottomInset + max((usableHeight - (usedHeight + CGFloat(5) * spacing)) / 2, 0)

        let slots = (0..<6).map { index in
            let position = 6 - index
            let y = startY + CGFloat(index) * (slot + spacing)
            let rect = CGRect(x: startX, y: y, width: slot, height: slot)
            return Slot(id: position, position: position, rect: rect)
        }

        let columnRect = CGRect(
            x: startX,
            y: slots.first?.rect.minY ?? startY,
            width: slot,
            height: (slots.last?.rect.maxY ?? startY) - (slots.first?.rect.minY ?? startY)
        )
        return Layout(columnRect: columnRect, slots: slots)
    }
}
