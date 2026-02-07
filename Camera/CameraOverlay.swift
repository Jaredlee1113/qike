import SwiftUI

struct CameraOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            overlayContent(in: geometry)
        }
        .ignoresSafeArea()
    }

    private func overlayContent(in geometry: GeometryProxy) -> some View {
        let layout = SlotLayout.layoutNormalized(in: geometry.size)
        let columnRect = layout.columnRect
        return ZStack {
            columnGuide(rect: columnRect, fullHeight: geometry.size.height)
        }
    }

    private func columnGuide(rect: CGRect, fullHeight: CGFloat) -> some View {
        Path { path in
            let top = max(rect.minY, 0)
            let bottom = min(rect.maxY, fullHeight)
            path.move(to: CGPoint(x: rect.minX, y: top))
            path.addLine(to: CGPoint(x: rect.minX, y: bottom))
            path.move(to: CGPoint(x: rect.maxX, y: top))
            path.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        }
        .stroke(Color.blue.opacity(0.9), lineWidth: 2)
    }
}

#if DEBUG
struct CameraOverlay_Previews: PreviewProvider {
    static var previews: some View {
        CameraOverlay()
            .frame(width: 400, height: 800)
            .background(Color.black.opacity(0.8))
    }
}
#endif
