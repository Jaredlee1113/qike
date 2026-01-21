import SwiftUI

struct CameraOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            overlayContent(in: geometry)
        }
        .ignoresSafeArea()
    }

    private func overlayContent(in geometry: GeometryProxy) -> some View {
        let slots = SlotLayout.slots(in: geometry.size)
        return ZStack {
            ForEach(slots) { slot in
                let rect = slot.rect
                let labelCenter = SlotLayout.labelCenter(for: rect)

                labelView(position: slot.position)
                    .frame(width: SlotLayout.labelWidth)
                    .position(labelCenter)

                slotView(size: rect.size)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func labelView(position: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(position)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(position <= 3 ? "下卦" : "上卦")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .shadow(color: Color.black.opacity(0.7), radius: 2, x: 0, y: 1)
    }

    private func slotView(size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.25))

            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.9), lineWidth: 2)

            Image(systemName: "circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.6))
                .shadow(color: Color.black.opacity(0.5), radius: 2, x: 0, y: 1)
        }
        .frame(width: size.width, height: size.height)
    }
}

#Preview {
    CameraOverlay()
        .frame(width: 400, height: 800)
        .background(Color.black.opacity(0.8))
}
