import SwiftUI

struct ManualInputView: View {
    @EnvironmentObject var dataStorage: DataStorageManager
    @Environment(\.dismiss) private var dismiss
    @State private var yaos: [YinYang] = [.yang, .yang, .yang, .yang, .yang, .yang]
    @State private var showingResult = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 标题说明
                VStack(spacing: 6) {
                    Text("手动输入卦象")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("从下到上依次选择第1-6爻的阴阳")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                // 当前卦象预览（从上到下：上爻→初爻）
                VStack(spacing: 8) {
                    Text("当前卦象")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(spacing: 6) {
                        // 从上到下显示：上爻(index 5) → 初爻(index 0)
                        ForEach((0..<6).reversed(), id: \.self) { index in
                            YaoSymbol(yinYang: yaos[index])
                                .frame(width: 100, height: 26)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }

                // 6个爻的选择器（从上到下：上爻→初爻）
                VStack(spacing: 12) {
                    // index 0 = 初爻(下卦), index 5 = 上爻(上卦)
                    // 从上往下排列：position 6, 5, 4, 3, 2, 1
                    ForEach((0..<6).reversed(), id: \.self) { index in
                        let position = index + 1  // index 0→position 1, index 5→position 6
                        YaoPicker(
                            position: position,
                            selection: $yaos[index]
                        )
                    }
                }

                // 查看结果按钮
                Button(action: {
                    saveManualSession()
                    showingResult = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.headline)

                        Text("查看结果")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("手动输入")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") {
                    dismiss()
                }
            }
        }
        .navigationDestination(isPresented: $showingResult) {
            ResultView(yaos: yaos)
        }
    }

    private func saveManualSession() {
        let results = yaos.enumerated().map { index, yinYang in
            CoinResult(
                position: index + 1,
                yinYang: yinYang,
                side: yinYang == .yin ? .front : .back,
                confidence: 1.0
            )
        }

        let _ = dataStorage.createSession(
            source: .manual,
            profileId: dataStorage.activeProfile?.id,
            results: results
        )
    }
}

struct YaoPicker: View {
    let position: Int
    @Binding var selection: YinYang

    var body: some View {
        HStack(spacing: 8) {
            // 位置标签
            VStack(spacing: 2) {
                Text("\(position)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(position <= 3 ? "下卦" : "上卦")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 40)

            // 阴阳选择器
            HStack(spacing: 8) {
                // 阳选项
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = .yang
                    }
                }) {
                    VStack(spacing: 2) {
                        YaoSymbol(yinYang: .yang)
                            .frame(width: 50, height: 35)

                        Text("阳")
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(selection == .yang ? Color.blue.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selection == .yang ? Color.blue : Color.clear, lineWidth: 2)
                    )
                }

                // 阴选项
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = .yin
                    }
                }) {
                    VStack(spacing: 2) {
                        YaoSymbol(yinYang: .yin)
                            .frame(width: 50, height: 35)

                        Text("阴")
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(selection == .yin ? Color.blue.opacity(0.15) : Color.clear)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selection == .yin ? Color.blue : Color.clear, lineWidth: 2)
                    )
                }
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
}

struct YaoSymbol: View {
    let yinYang: YinYang

    var body: some View {
        Group {
            if yinYang == .yang {
                // 阳爻：实线
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary)
                    .frame(height: 14)
            } else {
                // 阴爻：两条断线
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary)
                        .frame(height: 14)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary)
                        .frame(height: 14)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
struct ManualInputView_Previews: PreviewProvider {
    static var previews: some View {
        ManualInputView()
            .environmentObject(DataStorageManager.shared)
    }
}
#endif
