import SwiftUI

/// 输入模式
enum InputMode: String, CaseIterable {
    case symbol = "符号"
    case coin = "铜钱"
}

struct CameraView: View {
    @EnvironmentObject var dataStorage: DataStorageManager
    @EnvironmentObject var templateManager: CoinTemplateStorageManager
    @Environment(\.dismiss) private var dismiss

    // 两种模式各自独立的数据
    @State private var symbolYaos: [YinYang] = [.yang, .yang, .yang, .yang, .yang, .yang]
    @State private var coinYaos: [YinYang] = [.yang, .yang, .yang, .yang, .yang, .yang]
    @State private var inputMode: InputMode = .coin  // 默认为铜钱模式
    @State private var showingResult = false
    @State private var showingTemplateSetup = false

    // 当前模式对应的数据
    private var currentYaos: [YinYang] {
        inputMode == .symbol ? symbolYaos : coinYaos
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 标题说明
                headerSection

                // 输入模式切换
                modePicker

                // 主输入区域：左右融合卡片
                mainInputCard

                // 查看结果按钮
                resultButton
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("起课")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 铜钱模式下显示模板设置按钮
            if inputMode == .coin {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingTemplateSetup = true }) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("templateSetupButton")
                }
            }
        }
        .navigationDestination(isPresented: $showingResult) {
            ResultView(yaos: currentYaos)
        }
        .sheet(isPresented: $showingTemplateSetup) {
            NavigationView {
                CoinTemplateSetupView()
                    .environmentObject(templateManager)
            }
        }
    }

    // MARK: - 标题区域
    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("起课")
                .font(.title2)
                .fontWeight(.bold)

            Text(inputMode == .symbol ? "点击符号切换阴阳，从上到下依次为上爻到初爻" : "点击铜钱切换正反面，从上到下依次为上爻到初爻")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - 模式选择器
    private var modePicker: some View {
        Picker("输入模式", selection: $inputMode) {
            ForEach(InputMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("inputModePicker")
        .padding(.horizontal, 4)
    }

    // MARK: - 主输入卡片（左右融合）
    private var mainInputCard: some View {
        VStack(spacing: 0) {
            // 卡片标题
            HStack {
                Text("卦象")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // 当前卦名
                if let hexagram = HexagramProvider.findHexagram(by: currentYaos) {
                    Text(hexagram.name)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            // 左右分栏内容
            HStack(alignment: .top, spacing: 0) {
                // 左侧：输入区域
                inputSection
                    .frame(maxWidth: .infinity)

                // 中间分隔线
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1)

                // 右侧：卦象显示区域
                hexagramDisplaySection
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - 左侧输入区域
    private var inputSection: some View {
        VStack(spacing: 8) {
            Text("点击选择")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)

            if inputMode == .symbol {
                // 符号选择模式：直接显示爻符号，点击切换
                symbolInputSection
            } else {
                // 铜钱选择模式：显示铜钱图片，点击切换
                coinInputSection
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - 符号输入区域（点击符号切换阴阳）
    private var symbolInputSection: some View {
        VStack(spacing: 12) {
            // 从上到下显示：上爻(index 5) → 初爻(index 0)
            ForEach((0..<6).reversed(), id: \.self) { index in
                ClickableYaoSymbol(
                    yinYang: $symbolYaos[index],
                    position: index + 1
                )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 铜钱输入区域（点击铜钱切换正反面）
    private var coinInputSection: some View {
        Group {
            if let template = templateManager.selectedTemplate {
                VStack(spacing: 12) {
                    // 从上到下显示：上爻(index 5) → 初爻(index 0)
                    ForEach((0..<6).reversed(), id: \.self) { index in
                        ClickableCoinView(
                            yinYang: $coinYaos[index],
                            template: template,
                            templateManager: templateManager
                        )
                    }

                    // 模板名称
                    Text("模板：\(template.name)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // 无模板提示
                VStack(spacing: 12) {
                    Spacer()

                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("请先设置模板")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { showingTemplateSetup = true }) {
                        Text("设置模板")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .accessibilityIdentifier("setupTemplateButton")

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 右侧卦象显示区域
    private var hexagramDisplaySection: some View {
        VStack(spacing: 8) {
            Text("卦象")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)

            Spacer()

            // 卦象符号显示（从上到下：上爻→初爻）
            VStack(spacing: 4) {
                ForEach((0..<6).reversed(), id: \.self) { index in
                    YaoSymbol(yinYang: currentYaos[index])
                        .frame(width: 80, height: 20)
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)

            // 卦名
            if let hexagram = HexagramProvider.findHexagram(by: currentYaos) {
                VStack(spacing: 4) {
                    Text(hexagram.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(hexagram.id < 28 ? "上经" : "下经")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - 查看结果按钮
    private var resultButton: some View {
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
        .accessibilityIdentifier("viewResultButton")
    }

    // MARK: - 保存
    private func saveManualSession() {
        let results = currentYaos.enumerated().map { index, yinYang in
            CoinResult(
                position: index + 1,
                yinYang: yinYang,
                side: yinYang == .yin ? .front : .back,
                confidence: 1.0
            )
        }

        let _ = dataStorage.createSession(
            source: .manual,
            profileId: nil,
            results: results
        )
    }
}

// MARK: - 可点击的爻符号（符号模式）
struct ClickableYaoSymbol: View {
    @Binding var yinYang: YinYang
    let position: Int

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                yinYang = yinYang == .yang ? .yin : .yang
            }
        }) {
            HStack(spacing: 8) {
                // 位置标签
                Text("\(position)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                // 可点击的爻符号
                YaoSymbol(yinYang: yinYang)
                    .frame(width: 60, height: 24)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(yinYang == .yang ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(yinYang == .yang ? Color.blue : Color.orange, lineWidth: 1.5)
                    )
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 可点击的铜钱视图（铜钱模式）
struct ClickableCoinView: View {
    @Binding var yinYang: YinYang
    let template: CoinTemplate
    let templateManager: CoinTemplateStorageManager

    @State private var frontImage: Image?
    @State private var backImage: Image?

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                yinYang = yinYang == .yang ? .yin : .yang
            }
        }) {
            HStack(spacing: 12) {
                // 位置标签（阴阳）
                Text("\(yinYang == .yang ? "阳" : "阴")")
                    .font(.caption)
                    .foregroundColor(yinYang == .yang ? .blue : .orange)
                    .frame(width: 30)

                // 铜钱图片
                ZStack {
                    if let coinImage = (yinYang == .yang ? backImage : frontImage) {
                        coinImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(yinYang == .yang ? Color.blue : Color.orange, lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    } else {
                        // 默认圆形占位
                        Circle()
                            .fill(yinYang == .yang ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "questionmark")
                                    .foregroundColor(yinYang == .yang ? .blue : .orange)
                            )
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImages()
        }
    }

    private func loadImages() {
        if let uiFront = templateManager.loadImage(named: template.frontImageName) {
            frontImage = Image(uiImage: uiFront)
        }
        if let uiBack = templateManager.loadImage(named: template.backImageName) {
            backImage = Image(uiImage: uiBack)
        }
    }
}

// MARK: - 爻符符号
struct YaoSymbol: View {
    let yinYang: YinYang

    var body: some View {
        Group {
            if yinYang == .yang {
                // 阳爻：实线
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary)
                    .frame(height: 10)
            } else {
                // 阴爻：两条断线
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary)
                        .frame(height: 10)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary)
                        .frame(height: 10)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
            .environmentObject(DataStorageManager.shared)
            .environmentObject(CoinTemplateStorageManager.shared)
    }
}
#endif
