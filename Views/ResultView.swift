import SwiftUI

struct ResultView: View {
    let yaos: [YinYang]
    @State private var showingShare = false
    
    private var hexagram: Hexagram? {
        HexagramProvider.findHexagram(by: yaos)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let hexagram {
                    HexagramDisplay(hexagram: hexagram)
                } else {
                    Text("未找到对应的卦象")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("卦象结果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("分享") {
                    showingShare = true
                }
                .disabled(hexagram == nil)
            }
        }
        .sheet(isPresented: $showingShare) {
            if let hexagram {
                ActivityView(activityItems: [shareText(for: hexagram)])
            }
        }
    }

    private func shareText(for hexagram: Hexagram) -> String {
        [
            "卦名：\(hexagram.name)",
            "卦序：\(hexagram.id)",
            "",
            hexagram.explanation
        ].joined(separator: "\n")
    }
}

struct HexagramDisplay: View {
    let hexagram: Hexagram
    @State private var isDiagramExpanded = true
    @State private var isExplanationExpanded = false
    @State private var showingImageViewer = false
    private let cornerRadius: CGFloat = 18
    private let accentTint = Color(red: 0.20, green: 0.36, blue: 0.58)

    private var extractedImageExplanation: String {
        extractImageExplanation(from: hexagram.explanation)
    }

    var body: some View {
        VStack(spacing: 18) {
            headerCard

            if let image = loadImage(named: croppedImageName(for: hexagram.id)) ?? loadImage(named: hexagramImageName(for: hexagram.id)) {
                VStack(alignment: .leading, spacing: 8) {
                    imagePreviewCard(image: image)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 34))
                        .foregroundColor(accentTint.opacity(0.9))
                    Text("占卜图")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            }

            expandableCard(
                title: "占卜图解",
                subtitle: "图象与卦义提示",
                isExpanded: $isDiagramExpanded
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hexagram.divinationDiagramName)
                            .font(.headline)
                            .foregroundColor(accentTint)
                        Text(hexagram.divinationDiagram)
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }

                    if !extractedImageExplanation.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("图像解释")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(accentTint)
                            Text(extractedImageExplanation)
                                .font(.body)
                                .lineSpacing(4.5)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            expandableCard(
                title: "爻辞与卦解",
                subtitle: "逐爻说明与整体解释",
                isExpanded: $isExplanationExpanded
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("六爻")
                            .font(.subheadline.weight(.semibold))

                        ForEach(Array(hexagram.yaoci.enumerated()), id: \.offset) { index, yaoText in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(6 - index)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 18, alignment: .leading)
                                Text(yaoText)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    let mainExplanation = extractMainExplanation(from: hexagram.explanation)
                    if !mainExplanation.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("卦象解释")
                                .font(.subheadline.weight(.semibold))
                            Text(mainExplanation)
                                .font(.body)
                                .lineSpacing(5)
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Text(hexagram.hexagramSymbol)
                .font(.system(size: 56, weight: .medium))
                .frame(width: 84, height: 92)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accentTint.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(hexagram.name)
                    .font(.title2.weight(.bold))
                Text("第 \(hexagram.id) 卦")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                Label("点击图像放大，图解区查看卦像解释", systemImage: "viewfinder")
                    .font(.caption)
                    .foregroundColor(accentTint.opacity(0.95))
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentTint.opacity(0.12),
                            Color(.secondarySystemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func imagePreviewCard(image: UIImage) -> some View {
        VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 340)
                .padding(10)
                .contentShape(Rectangle())
                .onTapGesture {
                    showingImageViewer = true
                }

            HStack(spacing: 6) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                Text("点击图像查看大图")
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 11)
            .background(Color.black.opacity(0.03))
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .fullScreenCover(isPresented: $showingImageViewer) {
            ImageLightboxView(
                image: image,
                title: "\(hexagram.name) · 卦象图"
            )
        }
    }

    private func expandableCard<Content: View>(
        title: String,
        subtitle: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded.wrappedValue ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundColor(accentTint.opacity(0.85))
                }
                .padding(15)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                Divider()
                    .padding(.horizontal, 15)

                content()
                    .padding(.horizontal, 15)
                    .padding(.top, 10)
                    .padding(.bottom, 15)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.07), lineWidth: 1)
        )
    }

    private func hexagramImageName(for id: Int) -> String {
        let paddedId = String(format: "%02d", id)
        return "hexagram_\(paddedId)"
    }

    private func croppedImageName(for id: Int) -> String {
        let paddedId = String(format: "%02d", id)
        return "hexagram_crop_\(paddedId)"
    }

    private func loadImage(named: String) -> UIImage? {
        let filename = "\(named).png"

        if let image = UIImage(named: named) ?? UIImage(named: filename) {
            return image
        }

        if let path = Bundle.main.path(forResource: "HexagramImages/\(named)", ofType: "png") {
            if let image = UIImage(contentsOfFile: path) {
                return image
            }
        }

        if let url = Bundle.main.url(forResource: filename, withExtension: nil),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }

        return nil
    }

    private func extractImageExplanation(from text: String) -> String {
        if let range = text.range(of: "【卦图象解】", options: .literal) {
            let start = range.upperBound
            if let end = text.range(of: "【卦义解读】", options: .literal, range: start..<text.endIndex) {
                return String(text[start..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func extractMainExplanation(from text: String) -> String {
        var result = text

        if let range = text.range(of: "【卦图象解】", options: .literal) {
            result = String(text[..<range.lowerBound])
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ImageLightboxView: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dismissDragY: CGFloat = 0

    private var backgroundOpacity: Double {
        let opacity = 1 - (dismissDragY / 380)
        return max(0.35, min(1, opacity))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            if scale > 1 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            } else {
                                let y = value.translation.height
                                // Dampen tiny finger noise to avoid visible jitter while dragging to dismiss.
                                if y <= 2 {
                                    dismissDragY = 0
                                } else {
                                    dismissDragY = min(280, y * 0.92)
                                }
                            }
                        }
                        .onEnded { _ in
                            if scale > 1 {
                                lastOffset = offset
                            } else if dismissDragY > 140 {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                    dismissDragY = 0
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(baseScale * value, 1), 4)
                            if scale <= 1.01 {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                        .onEnded { value in
                            baseScale = min(max(baseScale * value, 1), 4)
                            scale = baseScale
                            if scale <= 1.01 {
                                offset = .zero
                                lastOffset = .zero
                                dismissDragY = 0
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if scale > 1 {
                            scale = 1
                            baseScale = 1
                            offset = .zero
                            lastOffset = .zero
                            dismissDragY = 0
                        } else {
                            scale = 2
                            baseScale = 2
                        }
                    }
                }
                .padding(.horizontal, 8)
                .offset(y: dismissDragY)

            VStack(spacing: 10) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.95))
                    }
                }

                Text("双击切换缩放，双指缩放拖动，下拉可关闭")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(Color.black.opacity(0.45))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#if DEBUG
struct ResultView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ResultView(yaos: [.yang, .yang, .yang, .yang, .yang, .yang])
        }
    }
}
#endif
