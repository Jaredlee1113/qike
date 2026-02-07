import SwiftUI
import SwiftData

struct ResultView: View {
    let yaos: [YinYang]
    @State private var showingShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let hexagram = HexagramProvider.findHexagram(by: yaos) {
                    HexagramDisplay(hexagram: hexagram)
                } else {
                    Text("未找到对应的卦象")
                        .font(.title2)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding()
        }
        .navigationTitle("卦象结果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("分享") {
                    showingShare = true
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            if let hexagram = HexagramProvider.findHexagram(by: yaos) {
                ActivityView(activityItems: [hexagram.name + "\n" + hexagram.explanation])
            }
        }
    }
}

struct HexagramDisplay: View {
    let hexagram: Hexagram
    @State private var isDiagramExpanded = false
    @State private var isExplanationExpanded = false

    var body: some View {
        VStack(spacing: 16) {
            // 1. 卦符和卦名
            HStack {
                Text(hexagram.hexagramSymbol)
                    .font(.system(size: 64))
                    .frame(width: 80)

                VStack(alignment: .leading, spacing: 8) {
                    Text(hexagram.name)
                        .font(.title)
                        .fontWeight(.bold)
                    Text("卦序: \(hexagram.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.08))
            .cornerRadius(12)

            // 2. 占卜图
            if let image = loadImage(named: hexagramImageName(for: hexagram.id)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .cornerRadius(12)
                    .shadow(radius: 2)
            } else {
                // 图片加载失败时的占位符
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("占卜图")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }

            // 3. 占卜图解+卦图象解（可折叠）
            VStack(spacing: 0) {
                // 折叠/展开按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isDiagramExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text("占卜图解")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: isDiagramExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                // 展开内容
                if isDiagramExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        // 占卜图解
                        VStack(alignment: .leading, spacing: 8) {
                            Text(hexagram.divinationDiagramName)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                            Text(hexagram.divinationDiagram)
                                .font(.body)
                        }

                        Divider()

                        // 从explanation中提取卦图象解部分
                        VStack(alignment: .leading, spacing: 8) {
                            Text("卦图象解")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(extractImageExplanation(from: hexagram.explanation))
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    .transition(.opacity)
                }
            }
            .background(Color.orange.opacity(0.05))
            .cornerRadius(12)

            // 4. 爻辞与卦解（可折叠）
            VStack(spacing: 0) {
                // 折叠/展开按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExplanationExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text("爻辞与卦解")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: isExplanationExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                // 展开内容
                if isExplanationExpanded {
                    VStack(alignment: .leading, spacing: 16) {
                        // 六爻
                        VStack(alignment: .leading, spacing: 10) {
                            Text("六爻")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            ForEach(0..<hexagram.yaoci.count, id: \.self) { index in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("第\(6 - index)爻")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 50, alignment: .leading)

                                    Text(hexagram.yaoci[index])
                                        .font(.body)
                                }
                            }
                        }

                        Divider()

                        // 卦象解释（剩余部分）
                        VStack(alignment: .leading, spacing: 8) {
                            Text("卦象解释")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(extractMainExplanation(from: hexagram.explanation))
                                .font(.body)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    .transition(.opacity)
                }
            }
            .background(Color.purple.opacity(0.05))
            .cornerRadius(12)
        }
    }

    private func hexagramImageName(for id: Int) -> String {
        let paddedId = String(format: "%02d", id)
        return "hexagram_\(paddedId)"
    }

    // 加载卦象图片
    private func loadImage(named: String) -> UIImage? {
        // 尝试多种加载方式
        let filename = "\(named).png"

        // 方式1: 从Bundle资源加载
        if let image = UIImage(named: filename) {
            print("✅ 通过UIImage(named:)加载: \(filename)")
            return image
        }

        // 方式2: 从Bundle路径加载
        if let path = Bundle.main.path(forResource: "HexagramImages/\(named)", ofType: "png") {
            if let image = UIImage(contentsOfFile: path) {
                print("✅ 通过路径加载: \(path)")
                return image
            }
        }

        // 方式3: 尝试主Bundle中的资源
        if let url = Bundle.main.url(forResource: filename, withExtension: nil),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            print("✅ 通过Bundle URL加载: \(filename)")
            return image
        }

        print("❌ 无法加载图片: \(filename)")
        return nil
    }

    // 提取卦图象解部分
    private func extractImageExplanation(from text: String) -> String {
        if let range = text.range(of: "【卦图象解】", options: .literal) {
            let start = range.upperBound
            if let end = text.range(of: "【卦义解读】", options: .literal, range: start..<text.endIndex) {
                return String(text[start..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // 如果没有找到【卦义解读】，取到末尾
            return String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    // 提取主要卦象解释（排除卦图象解）
    private func extractMainExplanation(from text: String) -> String {
        var result = text

        // 移除卦图象解部分
        if let range = text.range(of: "【卦图象解】", options: .literal) {
            result = String(text[..<range.lowerBound])
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
