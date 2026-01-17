import SwiftUI
import AVFoundation

struct CameraView: View {
    @EnvironmentObject var dataStorage: DataStorageManager

    @StateObject private var cameraManager = CameraManager()
    @State private var capturedImage: UIImage?
    @State private var showingResult = false
    @State private var processing = false
    @State private var errorMessage: String?
    @State private var showingAlert = false
    @State private var showingSetupProfile = false

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 相机预览
                CameraPreview(session: cameraManager.sessionProxy, isRunning: $cameraManager.isSessionRunning)
                    .edgesIgnoringSafeArea(.all)

                // 槽位覆盖层
                if capturedImage == nil {
                    CameraOverlay()
                        .allowsHitTesting(false)
                }

                // UI层
                uiLayer
            }
            .navigationTitle("起课")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SetupProfileView()) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white)
                    }
                }
            }
            .onAppear {
                if dataStorage.profiles.isEmpty {
                    errorMessage = "请先设置铜钱模板"
                    showingAlert = true
                }
                if !isUITesting {
                    cameraManager.startSession()
                }
            }
            .onDisappear {
                cameraManager.stopSession()
            }
            .alert("提示", isPresented: $showingAlert) {
                Button("确定", role: .cancel) {
                    if dataStorage.profiles.isEmpty {
                        showingSetupProfile = true
                    }
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .sheet(isPresented: $showingResult) {
                if let lastSession = dataStorage.getSortedSessions().first,
                   let yaos = lastSession.results?.map({ $0.yinYang }) {
                    ResultView(yaos: yaos)
                }
            }
            .navigationDestination(isPresented: $showingSetupProfile) {
                SetupProfileView()
            }
        }
    }

    @ViewBuilder
    private var uiLayer: some View {
        if let image = capturedImage {
            // 拍摄后的预览界面
            previewLayer(image: image)
        } else {
            // 拍摄前的取景界面
            captureLayer
        }
    }

    private func previewLayer(image: UIImage) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                // 预览图片
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 250)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue, lineWidth: 2)
                    )

                // 操作按钮
                HStack(spacing: 16) {
                    Button(action: {
                        capturedImage = nil
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.title2)
                            Text("重拍")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.8))
                        .cornerRadius(12)
                    }

                    Button(action: {
                        processImage()
                    }) {
                        VStack(spacing: 4) {
                            if processing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                Text("识别")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(processing ? Color.gray : Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(processing || dataStorage.profiles.isEmpty)
                }
            }
            .padding()
            .background(Color.black.opacity(0.85))
            .cornerRadius(16)
            .padding()
        }
    }

    private var captureLayer: some View {
        VStack {
            // 顶部提示
            VStack(spacing: 8) {
                Text("将铜钱对齐到槽位中")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("每行放一枚铜钱，从上到下依次为第1-6爻")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding()
            .background(Color.black.opacity(0.6))
            .cornerRadius(10)

            Spacer()

            // 底部拍摄按钮
            Button(action: {
                cameraManager.capturePhoto { image in
                    capturedImage = image
                }
            }) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 80, height: 80)

                        Circle()
                            .stroke(Color.blue, lineWidth: 4)
                            .frame(width: 70, height: 70)

                        Circle()
                            .fill(Color.blue)
                            .frame(width: 60, height: 60)
                    }

                    Text("点击拍摄")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(20)
                }
            }
            .padding(.bottom, 40)
        }
        .padding(.top, 60)
    }

    private func processImage() {
        guard !dataStorage.profiles.isEmpty else {
            errorMessage = "请先设置铜钱模板"
            showingAlert = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingSetupProfile = true
            }
            return
        }

        guard let image = capturedImage else { return }

        processing = true

        Task {
            do {
                let profile = dataStorage.profiles.first!
                let viewSize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)

                let roiImages = ROICropper.cropAllROIs(from: image, in: viewSize)

                let validationResults = await CoinValidator.validateAllCoins(roiImages)
                let validROIs = roiImages.filter { (image, position) in
                    validationResults.first { $0.0 == position }?.1 ?? false
                }

                guard validROIs.count == 6 else {
                    errorMessage = "请确保所有6个槽位都有铜钱"
                    showingAlert = true
                    processing = false
                    return
                }

                guard let frontTemplateData = TemplateManager.deserializeTemplateData(profile.frontTemplates),
                      let backTemplateData = TemplateManager.deserializeTemplateData(profile.backTemplates) else {
                    errorMessage = "模板数据错误，请重新设置"
                    showingAlert = true
                    processing = false
                    return
                }

                let frontTemplates = frontTemplateData.getObservations()
                let backTemplates = backTemplateData.getObservations()

                let results = await FeatureMatchService.matchAllCoins(
                    roiImages: validROIs,
                    frontTemplates: frontTemplates,
                    backTemplates: backTemplates
                )

                let validResults = results.filter { $0.confidence > 0.3 }

                guard validResults.count == 6 else {
                    errorMessage = "识别置信度不足，请重新拍摄"
                    showingAlert = true
                    processing = false
                    return
                }

                let session = dataStorage.createSession(
                    source: "camera",
                    profileId: profile.id,
                    results: validResults
                )

                let yaos = validResults.map { $0.yinYang }

                await MainActor.run {
                    processing = false
                    capturedImage = nil
                    showingResult = true
                }

            } catch {
                errorMessage = "识别失败: \(error.localizedDescription)"
                showingAlert = true
                processing = false
            }
        }
    }
}

#Preview {
    CameraView()
}
