import SwiftUI

/// 铜钱排列输入视图
struct CoinArrangementView: View {
    @ObservedObject var templateManager: CoinTemplateStorageManager
    @Binding var yaos: [YinYang]

    var body: some View {
        VStack(spacing: 20) {
            // 标题说明
            VStack(spacing: 6) {
                Text("铜钱排列")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("点击铜钱切换正反面，从上到下依次为上爻到初爻")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            if let template = templateManager.selectedTemplate {
                // 铜钱排列区域
                VStack(spacing: 12) {
                    // 从上到下显示：上爻(index 5) → 初爻(index 0)
                    ForEach((0..<6).reversed(), id: \.self) { index in
                        CoinRow(
                            position: index + 1,
                            yinYang: $yaos[index],
                            template: template,
                            templateManager: templateManager
                        )
                    }
                }

                // 模板名称
                Text("当前模板：\(template.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

            } else {
                // 没有模板时的提示
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    Text("请先设置铜钱模板")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("上传铜钱正反面照片后即可使用此输入方式")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    NavigationLink(destination: CoinTemplateSetupView()) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("设置模板")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 60)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

/// 单行铜钱组件
struct CoinRow: View {
    let position: Int
    @Binding var yinYang: YinYang
    let template: CoinTemplate
    let templateManager: CoinTemplateStorageManager

    @State private var frontImage: Image?
    @State private var backImage: Image?

    var body: some View {
        HStack(spacing: 12) {
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

            // 铜钱按钮
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    yinYang = yinYang == .yang ? .yin : .yang
                }
            }) {
                HStack(spacing: 16) {
                    // 阴阳标识
                    Text(yinYang == .yang ? "阳" : "阴")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(width: 30)

                    // 铜钱图片
                    ZStack {
                        if let coinImage = (yinYang == .yang ? backImage : frontImage) {
                            coinImage
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        } else {
                            // 默认圆形占位
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Image(systemName: "questionmark")
                                        .foregroundColor(.secondary)
                                )
                        }

                        // 选中指示器
                        Circle()
                            .stroke(yinYang == .yang ? Color.blue : Color.orange, lineWidth: 3)
                            .frame(width: 56, height: 56)
                    }

                    // 说明文字
                    VStack(alignment: .leading, spacing: 2) {
                        Text(yinYang == .yang ? "图案面" : "字面")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text(yinYang == .yang ? "──────" : "─  ─")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(yinYang == .yang ? .blue : .orange)
                    }

                    Spacer()

                    // 切换提示
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // 加载模板图片
    private func loadImages() {
        if let uiFront = templateManager.loadImage(named: template.frontImageName) {
            frontImage = Image(uiImage: uiFront)
        }
        if let uiBack = templateManager.loadImage(named: template.backImageName) {
            backImage = Image(uiImage: uiBack)
        }
    }
}

#if DEBUG
struct CoinArrangementView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CoinArrangementView(
                templateManager: CoinTemplateStorageManager.shared,
                yaos: .constant([.yang, .yang, .yang, .yang, .yang, .yang])
            )
        }
    }
}
#endif
