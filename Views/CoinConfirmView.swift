import SwiftUI

struct CoinConfirmView: View {
    let detections: [CoinDetector.DetectedCoin]
    let suggestedResults: [CoinResult]
    let isProcessing: Bool
    let onConfirm: ([CoinResult]) -> Void
    let onRetake: () -> Void
    let onRedetect: () -> Void

    @State private var selections: [Int: YinYang] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("确认每枚铜钱的阴阳")
                        .font(.headline)
                    Text("从上到下对应第6爻到第1爻")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    VStack(spacing: 12) {
                        if detections.isEmpty {
                            Text("未检测到铜钱，请重新检测或重新拍摄")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 40)
                        } else {
                            ForEach(sortedDetections, id: \.position) { detection in
                                HStack(spacing: 12) {
                                    Image(uiImage: detection.image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 72, height: 72)
                                        .background(Color.black.opacity(0.04))
                                        .cornerRadius(10)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("第\(detection.position)爻")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text(suggestionText(for: detection.position))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Picker("阴阳", selection: selectionBinding(for: detection.position)) {
                                        Text("阳").tag(YinYang.yang)
                                        Text("阴").tag(YinYang.yin)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 140)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.08))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                VStack(spacing: 10) {
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

                    Button("确认") {
                        onConfirm(buildResults())
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing || detections.count != 6)
                }
            }
            .padding()
            .navigationTitle("确认卦象")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isProcessing {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        ProgressView("检测中…")
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
        }
        .onAppear {
            resetSelections()
        }
        .onChange(of: detections.map { $0.rect }) { _ in
            resetSelections()
        }
    }

    private var sortedDetections: [CoinDetector.DetectedCoin] {
        detections.sorted { $0.position > $1.position }
    }

    private func resetSelections() {
        var next: [Int: YinYang] = [:]
        for detection in detections {
            if let suggestion = suggestedResults.first(where: { $0.position == detection.position }) {
                switch suggestion.side {
                case .front:
                    next[detection.position] = .yin
                case .back:
                    next[detection.position] = .yang
                case .uncertain, .invalid:
                    next[detection.position] = .yang
                }
            } else {
                next[detection.position] = .yang
            }
        }
        selections = next
    }

    private func selectionBinding(for position: Int) -> Binding<YinYang> {
        Binding(
            get: { selections[position] ?? .yang },
            set: { selections[position] = $0 }
        )
    }

    private func buildResults() -> [CoinResult] {
        let results = detections.map { detection -> CoinResult in
            let selection = selections[detection.position] ?? .yang
            let side: CoinSide = selection == .yin ? .front : .back
            return CoinResult(
                position: detection.position,
                yinYang: selection,
                side: side,
                confidence: 1.0
            )
        }
        return results.sorted { $0.position < $1.position }
    }

    private func suggestionText(for position: Int) -> String {
        guard let suggestion = suggestedResults.first(where: { $0.position == position }) else {
            return "请确认阴阳"
        }

        if suggestion.side == .uncertain || suggestion.side == .invalid {
            return "建议：不确定，请调整光线或重录模板"
        }

        let label = suggestion.side == .front ? "阴" : "阳"
        let confidenceText = String(format: "%.2f", suggestion.confidence)
        return "建议：\(label) 置信度 \(confidenceText)"
    }
}

#if DEBUG
struct CoinConfirmView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleImage = UIImage(systemName: "circle.fill") ?? UIImage()
        let sample = CoinDetector.DetectedCoin(
            image: sampleImage,
            maskedImage: nil,
            position: 6,
            rect: CGRect(x: 0, y: 0, width: 100, height: 100),
            normalizedRect: CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
        )
        return CoinConfirmView(
            detections: [sample, sample, sample, sample, sample, sample],
            suggestedResults: [],
            isProcessing: false,
            onConfirm: { _ in },
            onRetake: {},
            onRedetect: {}
        )
    }
}
#endif
