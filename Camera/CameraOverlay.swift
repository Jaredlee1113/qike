import SwiftUI

struct CameraOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            overlayContent(in: geometry)
        }
        .ignoresSafeArea()
    }

    private func overlayContent(in geometry: GeometryProxy) -> some View {
        // 槽位配置
        let slotSize: CGFloat = 100
        let slotSpacing: CGFloat = 16
        let totalHeight = CGFloat(6) * slotSize + CGFloat(5) * slotSpacing

        // 计算居中位置
        let screenWidth = geometry.size.width
        let screenHeight = geometry.size.height
        let startY = (screenHeight - totalHeight) / 2
        let centerX = screenWidth / 2 - slotSize / 2

        return ZStack {
            // 绘制6个槽位
            ForEach(0..<6, id: \.self) { index in
                let position = 6 - index
                let y = startY + CGFloat(index) * (slotSize + slotSpacing)

                slotView(at: CGPoint(x: centerX, y: y), size: slotSize, position: position)
            }
        }
    }

    private func slotView(at point: CGPoint, size: CGFloat, position: Int) -> some View {
        
        HStack(spacing: 12) {
            // 左侧标签
            VStack(spacing: 4) {
                Text("\(position)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(position <= 3 ? "上卦" : "下卦")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(width: 50)

            // 槽位
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))

                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white, lineWidth: 2)

                Image(systemName: "circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white.opacity(0.3))
            }
            .frame(width: size, height: size)
        }
        .position(x: point.x + 19, y: point.y + size / 2)
    }
}

#Preview {
    CameraOverlay()
        .frame(width: 400, height: 800)
        .background(Color.black.opacity(0.8))
}
