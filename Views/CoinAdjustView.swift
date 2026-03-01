import SwiftUI
import UIKit

struct CoinAdjustView: View {
    let image: UIImage
    let reason: DetectionFailureReason
    let isProcessing: Bool
    let onConfirm: ([DetectionDraft]) -> Void
    let onRedetect: () -> Void
    let onRetake: () -> Void

    @State private var drafts: [DetectionDraft]
    @State private var dragStartCenters: [UUID: CGPoint] = [:]

    init(
        image: UIImage,
        initialDrafts: [DetectionDraft],
        reason: DetectionFailureReason,
        isProcessing: Bool,
        onConfirm: @escaping ([DetectionDraft]) -> Void,
        onRedetect: @escaping () -> Void,
        onRetake: @escaping () -> Void
    ) {
        self.image = image
        self.reason = reason
        self.isProcessing = isProcessing
        self.onConfirm = onConfirm
        self.onRedetect = onRedetect
        self.onRetake = onRetake
        _drafts = State(initialValue: initialDrafts)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("微调铜钱位置")
                        .font(.headline)
                    Text(reason.hintText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 12) {
                    Button("重新检测") {
                        onRedetect()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)

                    Button("重新拍摄") {
                        onRetake()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                }

                Button("重新识别") {
                    onConfirm(submittableDrafts())
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || drafts.count != 6)
            }
            .padding()
            .navigationTitle("微调识别框")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isProcessing {
                    ZStack {
                        Color.black.opacity(0.42)
                            .ignoresSafeArea()
                        ProgressView("重新识别中…")
                            .padding()
                            .background(Color.black.opacity(0.75))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
        }
    }

    private var editor: some View {
        GeometryReader { geometry in
            let imageRect = Self.fittedRect(for: image.size, in: geometry.size)
            let mappedPositions = currentMappedPositions()

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.08)
                    .cornerRadius(12)

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)
                    .cornerRadius(12)

                ForEach(Array(drafts.enumerated()), id: \.element.id) { entry in
                    let index = entry.offset
                    let draft = entry.element
                    let rect = Self.rect(for: draft, in: imageRect)
                    let mappedPosition = mappedPositions[draft.id] ?? (draft.positionHint ?? 0)

                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.green, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.green.opacity(0.12))
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .gesture(
                            dragGesture(
                                for: index,
                                imageRect: imageRect
                            )
                        )

                    Text("第\(mappedPosition)爻")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                        .position(x: rect.midX, y: max(imageRect.minY + 10, rect.minY - 8))
                }
            }
        }
    }

    private func dragGesture(
        for index: Int,
        imageRect: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard drafts.indices.contains(index) else { return }
                let id = drafts[index].id
                let start = dragStartCenters[id] ?? drafts[index].centerNormalized
                if dragStartCenters[id] == nil {
                    dragStartCenters[id] = start
                }

                let dx = value.translation.width / max(imageRect.width, 1)
                let dy = value.translation.height / max(imageRect.height, 1)
                let halfWidth = drafts[index].sizeNormalized.width / 2
                let halfHeight = drafts[index].sizeNormalized.height / 2

                var next = CGPoint(x: start.x + dx, y: start.y + dy)
                next.x = min(max(next.x, halfWidth), 1 - halfWidth)
                next.y = min(max(next.y, halfHeight), 1 - halfHeight)
                drafts[index].centerNormalized = next
            }
            .onEnded { _ in
                guard drafts.indices.contains(index) else { return }
                let id = drafts[index].id
                dragStartCenters.removeValue(forKey: id)
            }
    }

    private func submittableDrafts() -> [DetectionDraft] {
        let sorted = drafts.sorted { $0.centerNormalized.y < $1.centerNormalized.y }
        return sorted.enumerated().map { index, draft in
            var next = draft
            next.positionHint = 6 - index
            return next
        }
    }

    private func currentMappedPositions() -> [UUID: Int] {
        let sorted = drafts.sorted { $0.centerNormalized.y < $1.centerNormalized.y }
        return sorted.enumerated().reduce(into: [UUID: Int]()) { partial, item in
            partial[item.element.id] = 6 - item.offset
        }
    }

    private static func fittedRect(
        for imageSize: CGSize,
        in containerSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / max(containerSize.height, 1)

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGRect(
                x: 0,
                y: (containerSize.height - height) / 2,
                width: width,
                height: height
            )
        }

        let height = containerSize.height
        let width = height * imageAspect
        return CGRect(
            x: (containerSize.width - width) / 2,
            y: 0,
            width: width,
            height: height
        )
    }

    private static func rect(
        for draft: DetectionDraft,
        in imageRect: CGRect
    ) -> CGRect {
        let width = draft.sizeNormalized.width * imageRect.width
        let height = draft.sizeNormalized.height * imageRect.height
        let centerX = imageRect.minX + (draft.centerNormalized.x * imageRect.width)
        let centerY = imageRect.minY + (draft.centerNormalized.y * imageRect.height)

        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }
}

#if DEBUG
struct CoinAdjustView_Previews: PreviewProvider {
    static var previews: some View {
        let image = UIImage(systemName: "photo") ?? UIImage()
        let drafts = (0..<6).map { index in
            DetectionDraft(
                centerNormalized: CGPoint(x: 0.5, y: 0.14 + CGFloat(index) * 0.14),
                sizeNormalized: CGSize(width: 0.2, height: 0.12),
                positionHint: 6 - index
            )
        }
        return CoinAdjustView(
            image: image,
            initialDrafts: drafts,
            reason: .qualityRejected,
            isProcessing: false,
            onConfirm: { _ in },
            onRedetect: {},
            onRetake: {}
        )
    }
}
#endif
