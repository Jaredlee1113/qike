import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

struct CameraView: View {
    @EnvironmentObject var dataStorage: DataStorageManager

    @StateObject private var cameraManager = CameraManager()
    @State private var capturedImage: UIImage?
    @State private var showingResult = false
    @State private var showingConfirm = false
    @State private var pendingShowResult = false
    @State private var processing = false
    @State private var processingStage: String?
    @State private var errorMessage: String?
    @State private var showingAlert = false
    @State private var showingSetupProfile = false
    @State private var showingManualInput = false
    @State private var showingPhotoPicker = false
    @State private var pickedImage: UIImage?
    @State private var detectedCoins: [CoinDetector.DetectedCoin] = []

    @State private var cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isRequestingPermission = false
    @State private var debugSaveImages = false
    @State private var debugShowOverlay = true
    @State private var debugMatchResults: [CoinResult] = []
    @State private var lastDebugFolderURL: URL?
    @State private var showingDebugShare = false
    @State private var debugShareItems: [Any] = []

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    private var isCameraAuthorized: Bool {
        cameraAuthorization == .authorized
    }

    private var isCameraReady: Bool {
        isCameraAuthorized && cameraManager.isSessionRunning
    }

    var body: some View {
        ZStack {
            CameraPreview(session: cameraManager.sessionProxy, isRunning: $cameraManager.isSessionRunning)
                .edgesIgnoringSafeArea(.all)

            uiLayer

            if capturedImage == nil {
                permissionOverlay
            }
        }
        .navigationTitle("起课")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if dataStorage.profiles.isEmpty {
                errorMessage = "请先设置铜钱模板"
                showingAlert = true
            }
            updateCameraAuthorization()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: showingConfirm) { isShowing in
            if !isShowing && pendingShowResult {
                pendingShowResult = false
                showingResult = true
            }
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
        .sheet(isPresented: $showingConfirm) {
            CoinConfirmView(
                detections: detectedCoins,
                isProcessing: processing,
                onConfirm: handleConfirm,
                onRetake: {
                    showingConfirm = false
                    capturedImage = nil
                    detectedCoins = []
                    debugMatchResults = []
                },
                onRedetect: {
                    runDetection(showConfirm: false)
                }
            )
        }
        .sheet(isPresented: $showingResult) {
            if let lastSession = dataStorage.getSortedSessions().first,
               let yaos = lastSession.results?.map({ $0.yinYang }) {
                ResultView(yaos: yaos)
            }
        }
        .sheet(isPresented: $showingManualInput) {
            NavigationStack {
                ManualInputView()
            }
        }
        .sheet(isPresented: $showingPhotoPicker) {
            SingleImagePicker(selectedImage: $pickedImage)
        }
        .sheet(isPresented: $showingDebugShare) {
            ActivityView(activityItems: debugShareItems)
        }
        .navigationDestination(isPresented: $showingSetupProfile) {
            SetupProfileView()
        }
    }

    @ViewBuilder
    private var uiLayer: some View {
        if let image = capturedImage {
            previewLayer(image: image)
        } else {
            captureLayer
        }
    }

    private var captureLayer: some View {
        Color.clear
            .safeAreaInset(edge: .top, spacing: 0) {
                topHint
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomControls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: pickedImage) { newImage in
                guard let image = newImage else { return }
                capturedImage = image
                pickedImage = nil
                detectedCoins = []
                debugMatchResults = []
                processImage()
            }
    }

    private var topHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("对齐铜钱")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                progressDots
            }

            Text("将6枚铜钱从上到下摆成一列，依次为第1-6爻")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))

            if isCameraAuthorized && !cameraManager.isSessionRunning {
                Text("相机启动中…")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == 0 ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            captureButton

            HStack(spacing: 12) {
                secondaryButton(title: "相册选择") {
                    showingPhotoPicker = true
                }

                secondaryButton(title: "手动输入") {
                    showingManualInput = true
                }

                secondaryButton(title: "设置模板") {
                    showingSetupProfile = true
                }
            }

            #if DEBUG
            VStack(spacing: 8) {
                Toggle("保存调试图", isOn: $debugSaveImages)
                Toggle("显示识别框", isOn: $debugShowOverlay)
                Button("导出调试图") {
                    prepareDebugShare()
                }
                .buttonStyle(.bordered)
                .disabled(lastDebugFolderURL == nil)
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            .font(.caption2)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
            #endif
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(16)
        }
    }

    private var captureButton: some View {
        let isEnabled = isCameraReady && !processing
        return Button(action: {
            triggerCaptureFeedback()
            cameraManager.capturePhoto { image in
                capturedImage = image
                detectedCoins = []
                debugMatchResults = []
            }
        }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 84, height: 84)

                    Circle()
                        .stroke(Color.blue, lineWidth: 4)
                        .frame(width: 74, height: 74)

                    Circle()
                        .fill(Color.blue)
                        .frame(width: 64, height: 64)
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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .padding(.bottom, 6)
    }

    private func previewLayer(image: UIImage) -> some View {
        ZStack {
            VStack {
                Spacer()

                VStack(spacing: 16) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 260)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                        #if DEBUG
                        .overlay {
                            if debugShowOverlay {
                                DebugCoinOverlay(
                                    image: image,
                                    detections: detectedCoins,
                                    results: debugMatchResults
                                )
                            }
                        }
                        #endif

                    HStack(spacing: 16) {
                        Button(action: {
                            capturedImage = nil
                            detectedCoins = []
                            debugMatchResults = []
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
                        .disabled(processing)
                        .opacity(processing ? 0.6 : 1)

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

            if processing {
                processingOverlay
            }
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))

                Text(processingStage ?? "识别中…")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(Color.black.opacity(0.75))
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var permissionOverlay: some View {
        switch cameraAuthorization {
        case .authorized:
            EmptyView()
        case .notDetermined:
            permissionCard(
                title: "需要相机权限",
                message: isRequestingPermission ? "正在请求相机权限…" : "请允许相机权限以开始起课",
                buttonTitle: isRequestingPermission ? "请求中…" : "允许相机",
                isButtonEnabled: !isRequestingPermission
            ) {
                requestCameraAccess()
            }
        case .denied, .restricted:
            permissionCard(
                title: "相机权限未开启",
                message: "请在系统设置中开启相机权限",
                buttonTitle: "去设置",
                isButtonEnabled: true
            ) {
                openAppSettings()
            }
        @unknown default:
            EmptyView()
        }
    }

    private func permissionCard(
        title: String,
        message: String,
        buttonTitle: String,
        isButtonEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(message)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button(action: action) {
                    Text(buttonTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .cornerRadius(16)
                }
                .disabled(!isButtonEnabled)
                .opacity(isButtonEnabled ? 1 : 0.7)
            }
            .padding()
            .background(Color.black.opacity(0.75))
            .cornerRadius(12)
            .padding(.horizontal, 24)
        }
    }

    private func updateCameraAuthorization() {
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)

        switch cameraAuthorization {
        case .authorized:
            if !isUITesting {
                cameraManager.startSession()
            }
        case .notDetermined:
            if !isUITesting {
                requestCameraAccess()
            }
        case .denied, .restricted:
            cameraManager.stopSession()
        @unknown default:
            break
        }
    }

    private func requestCameraAccess() {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.isRequestingPermission = false
                self.cameraAuthorization = granted ? .authorized : .denied
                if granted && !self.isUITesting {
                    self.cameraManager.startSession()
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func triggerCaptureFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    private func processImage() {
        runDetection(showConfirm: true)
    }

    private func runDetection(showConfirm: Bool) {
        guard !dataStorage.profiles.isEmpty else {
            errorMessage = "请先设置铜钱模板"
            showingAlert = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingSetupProfile = true
            }
            return
        }

        guard let image = capturedImage else { return }
        let normalizedImage = ImageProcessor.normalizeOrientation(image)

        debugLog("start process image size=\(image.size.width)x\(image.size.height) orientation=\(image.imageOrientation.rawValue)")
        debugLog("normalized image size=\(normalizedImage.size.width)x\(normalizedImage.size.height) orientation=\(normalizedImage.imageOrientation.rawValue)")

        processing = true
        processingStage = showConfirm ? "检测铜钱…" : "重新检测…"

        Task {
            do {
                await MainActor.run {
                    debugMatchResults = []
                }

                let foundCoins = await CoinDetector.detectCoins(from: normalizedImage)
                debugLog("detected coins count=\(foundCoins.count)")
                await MainActor.run {
                    detectedCoins = foundCoins
                }
                #if DEBUG
                if debugSaveImages {
                    saveDebugImages(original: normalizedImage, detections: foundCoins)
                }
                #endif

                guard foundCoins.count == 6 else {
                    await MainActor.run {
                        errorMessage = "未检测到6枚铜钱，请调整摆放或光线"
                        showingAlert = true
                        processing = false
                        processingStage = nil
                    }
                    return
                }

                await MainActor.run {
                    processing = false
                    processingStage = nil
                    if showConfirm {
                        showingConfirm = true
                    }
                }

            } catch {
                await MainActor.run {
                    errorMessage = "识别失败: \(error.localizedDescription)"
                    showingAlert = true
                    processing = false
                    processingStage = nil
                }
            }
        }
    }

    private func handleConfirm(results: [CoinResult]) {
        guard let profile = dataStorage.profiles.first else {
            errorMessage = "请先设置铜钱模板"
            showingAlert = true
            return
        }

        let _ = dataStorage.createSession(
            source: "camera",
            profileId: profile.id,
            results: results
        )

        capturedImage = nil
        detectedCoins = []
        debugMatchResults = []
        pendingShowResult = true
        showingConfirm = false
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("CameraView: \(message)")
        #endif
    }

    #if DEBUG
    private func saveDebugImages(original: UIImage, detections: [CoinDetector.DetectedCoin]) {
        DispatchQueue.global(qos: .utility).async {
            let timestamp = Int(Date().timeIntervalSince1970)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CoinDebug_\(timestamp)")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                print("CameraView: debug folder create failed \(error.localizedDescription)")
                return
            }

            if let data = original.jpegData(compressionQuality: 0.9) {
                let url = folder.appendingPathComponent("capture.jpg")
                try? data.write(to: url)
            }

            for detection in detections {
                let filename = String(format: "coin_%02d.jpg", detection.position)
                let url = folder.appendingPathComponent(filename)
                if let data = detection.image.jpegData(compressionQuality: 0.9) {
                    try? data.write(to: url)
                }
            }

            print("CameraView: debug images saved to \(folder.path)")
            DispatchQueue.main.async {
                self.lastDebugFolderURL = folder
            }
        }
    }

    private func prepareDebugShare() {
        guard let folder = lastDebugFolderURL else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        debugShareItems = files.isEmpty ? [folder] : files
        showingDebugShare = true
    }
    #endif
}

private struct DebugCoinOverlay: View {
    let image: UIImage
    let detections: [CoinDetector.DetectedCoin]
    let results: [CoinResult]

    var body: some View {
        GeometryReader { geo in
            let imageRect = Self.fittedRect(for: image.size, in: geo.size)
            ZStack {
                ForEach(detections, id: \.position) { detection in
                    let rect = Self.rect(for: detection.normalizedRect, in: imageRect)
                    Rectangle()
                        .stroke(Color.green, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    if let result = results.first(where: { $0.position == detection.position }) {
                        let label = Self.labelText(for: result)
                        let labelY = max(rect.minY - 10, imageRect.minY + 8)
                        Text(label)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(6)
                            .position(x: rect.midX, y: labelY)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func fittedRect(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        let imageAspect = imageSize.width / max(imageSize.height, 1)
        let containerAspect = containerSize.width / max(containerSize.height, 1)

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            let originY = (containerSize.height - height) / 2
            return CGRect(x: 0, y: originY, width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            let originX = (containerSize.width - width) / 2
            return CGRect(x: originX, y: 0, width: width, height: height)
        }
    }

    private static func rect(for normalizedRect: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.origin.x + normalizedRect.origin.x * imageRect.width,
            y: imageRect.origin.y + normalizedRect.origin.y * imageRect.height,
            width: normalizedRect.size.width * imageRect.width,
            height: normalizedRect.size.height * imageRect.height
        )
    }

    private static func labelText(for result: CoinResult) -> String {
        let confidence = String(format: "%.2f", result.confidence)
        return "\(result.position) \(result.side.rawValue) \(confidence)"
    }
}

struct SingleImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .images

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: SingleImagePicker

        init(_ parent: SingleImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else { return }
            let itemProvider = result.itemProvider

            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
                    guard let self = self else { return }
                    if let image = image as? UIImage {
                        DispatchQueue.main.async {
                            self.parent.selectedImage = image
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    CameraView()
}
