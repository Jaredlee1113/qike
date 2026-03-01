import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

struct CameraView: View {
    @EnvironmentObject var dataStorage: DataStorageManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var liveDetector = LiveDetectionController()
    @State private var capturedImage: UIImage?
    @State private var resultYaos: [YinYang] = []
    @State private var showingResult = false
    @State private var showingConfirm = false
    @State private var showingAdjust = false
    @State private var processing = false
    @State private var isCapturingPhoto = false
    @State private var processingStage: String?
    @State private var errorMessage: String?
    @State private var showingAlert = false
    @State private var shouldOpenTemplateCenterAfterAlert = false
    @State private var showingTemplateCenter = false
    @State private var showingManualInput = false
    @State private var showingPhotoPicker = false
    @State private var pickedImage: UIImage?
    @State private var detectedCoins: [CoinDetector.DetectedCoin] = []
    @State private var suggestedResults: [CoinResult] = []
    @State private var textCalibrationCache: [UUID: FeatureMatchService.TextCalibration] = [:]
    @State private var adjustmentDrafts: [DetectionDraft] = []
    @State private var adjustmentReason: DetectionFailureReason = .notEnoughCoins
    @State private var showAlignHint = true
    @State private var autoPresenting = false
    @State private var previewSize: CGSize = .zero

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

    private var uiTestFlags: CameraViewUITestFlags {
        CameraViewUITestFlags.current
    }

    private var shouldBypassTemplateRequirementForUITest: Bool {
        uiTestFlags.shouldBypassTemplateRequirement
    }

    private var isAutoDetectionFlowEnabled: Bool {
        if ProcessInfo.processInfo.arguments.contains("-force-legacy-detection-flow") {
            return false
        }
        if let override = UserDefaults.standard.object(forKey: "feature_auto_detection_flow_enabled") as? Bool {
            return override
        }
        return !uiTestFlags.forceLegacyDetection
    }

    private var isStrictSlotGuidedDetectionEnabled: Bool {
        if ProcessInfo.processInfo.arguments.contains("-disable-strict-slot-detection") {
            return false
        }
        #if DEBUG
        if let override = UserDefaults.standard.object(forKey: "feature_strict_slot_detection_enabled") as? Bool {
            return override
        }
        #endif
        return true
    }

    private var shouldAutoPresentLiveResult: Bool {
        false
    }

    private var layoutCheckStatusText: String {
        CameraViewUITestFlags.layoutStatusText(for: previewSize)
    }

    private var uiTestStatusText: String {
        if uiTestFlags.presenceCheck {
            return CameraViewUITestFlags.presenceStatusText()
        }
        if uiTestFlags.qualityCheck {
            return CameraViewUITestFlags.qualityStatusText()
        }
        if uiTestFlags.stabilityCheck {
            return CameraViewUITestFlags.stabilityStatusText()
        }
        if uiTestFlags.matchCheck {
            return CameraViewUITestFlags.matchStatusText()
        }
        if uiTestFlags.reliabilityCheck {
            return CameraViewUITestFlags.reliabilityStatusText()
        }
        if uiTestFlags.lowLightHintCheck {
            return "LOW_LIGHT_HINT_OK"
        }
        return layoutCheckStatusText
    }

    private var shouldShowTorchHint: Bool {
        (liveDetector.shouldSuggestTorch || cameraManager.isTorchOn || uiTestFlags.lowLightHintCheck) &&
            (cameraManager.hasTorch || uiTestFlags.lowLightHintCheck)
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

            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        updatePreviewSize(geo.size)
                    }
                    .onChange(of: geo.size) { newSize in
                        updatePreviewSize(newSize)
                    }
            }
            .allowsHitTesting(false)

            uiLayer

            if uiTestFlags.layoutCheck || uiTestFlags.presenceCheck || uiTestFlags.qualityCheck || uiTestFlags.stabilityCheck || uiTestFlags.matchCheck || uiTestFlags.reliabilityCheck || uiTestFlags.lowLightHintCheck {
                Text(uiTestStatusText)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                    .accessibilityIdentifier("uiTestStatus")
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if capturedImage == nil {
                permissionOverlay
            }
        }
        .navigationTitle("起课")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if dataStorage.activeProfile == nil && !shouldBypassTemplateRequirementForUITest {
                showAlert("请先设置铜钱模板", openTemplateCenter: true)
            }
            liveDetector.updateProfile(dataStorage.activeProfile)
            cameraManager.onFrame = { [weak liveDetector] pixelBuffer, _ in
                liveDetector?.handleFrame(pixelBuffer)
            }
            updateLiveDetectionState()
            updateCameraAuthorization()
            scheduleAlignHintDismissal()
            injectMockConfirmIfNeeded()
        }
        .onDisappear {
            cameraManager.setTorchEnabled(false)
            cameraManager.stopSession()
            cameraManager.onFrame = nil
            liveDetector.reset()
            isCapturingPhoto = false
        }
        .onReceive(dataStorage.$profiles) { _ in
            liveDetector.updateProfile(dataStorage.activeProfile)
            textCalibrationCache.removeAll()
        }
        .onReceive(dataStorage.$activeProfileId) { _ in
            liveDetector.updateProfile(dataStorage.activeProfile)
        }
        .onChange(of: capturedImage) { _ in
            updateLiveDetectionState()
        }
        .onChange(of: showingConfirm) { _ in
            updateLiveDetectionState()
        }
        .onChange(of: showingAdjust) { _ in
            updateLiveDetectionState()
        }
        .onReceive(liveDetector.$results) { results in
            guard shouldAutoPresentLiveResult else { return }
            guard capturedImage == nil, !showingResult, !showingConfirm else { return }
            guard isResultReady(results) else { return }
            guard hasReliableResults(results) else { return }
            detectedCoins = liveDetector.detections
            suggestedResults = results
            debugMatchResults = results
            showingConfirm = true
        }
        .onChange(of: showingResult) { newValue in
            if !newValue {
                autoPresenting = false
            }
            updateLiveDetectionState()
        }
        .alert("提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) {
                if shouldOpenTemplateCenterAfterAlert || dataStorage.activeProfile == nil {
                    shouldOpenTemplateCenterAfterAlert = false
                    showingTemplateCenter = true
                }
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .fullScreenCover(isPresented: $showingResult) {
            if !resultYaos.isEmpty {
                NavigationStack {
                    ResultView(yaos: resultYaos)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") {
                                    liveDetector.reset()
                                    cameraManager.stopSession()
                                    cameraManager.onFrame = nil
                                    resultYaos = []
                                    showingResult = false
                                    dismiss()
                                }
                            }
                        }
                }
            }
        }
        .fullScreenCover(isPresented: $showingConfirm) {
            CoinConfirmView(
                detections: detectedCoins,
                suggestedResults: suggestedResults,
                isProcessing: processing,
                onConfirm: handleConfirm,
                onRetake: {
                    showingConfirm = false
                    capturedImage = nil
                    detectedCoins = []
                    debugMatchResults = []
                    suggestedResults = []
                },
                onRedetect: {
                    if capturedImage != nil {
                        showingConfirm = false
                        runDetection(showConfirmAfterMatch: true)
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showingAdjust) {
            if let image = capturedImage {
                CoinAdjustView(
                    image: image,
                    initialDrafts: adjustmentDrafts,
                    reason: adjustmentReason,
                    isProcessing: processing,
                    onConfirm: { drafts in
                        showingAdjust = false
                        rerunDetectionWithAdjustedDrafts(drafts, showConfirmAfterMatch: true)
                    },
                    onRedetect: {
                        showingAdjust = false
                        runDetection(showConfirmAfterMatch: true)
                    },
                    onRetake: {
                        showingAdjust = false
                        capturedImage = nil
                        detectedCoins = []
                        debugMatchResults = []
                        suggestedResults = []
                    }
                )
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
        .navigationDestination(isPresented: $showingTemplateCenter) {
            TemplateCenterView()
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
        ZStack {
            CameraOverlay()
                .allowsHitTesting(false)

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
                    suggestedResults = []
                    processImage()
                }
        }
    }

    private var topHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showAlignHint {
                HStack {
                    Text("对齐铜钱")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    progressDots
                }

                Text("将6枚铜钱从上到下大致摆成一列，拍照后可拖动微调")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }

            if isCameraAuthorized && !cameraManager.isSessionRunning {
                Text("相机启动中…")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }

            Text(liveDetector.statusText)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))

            if isAutoDetectionFlowEnabled,
               !liveDetector.detections.isEmpty,
               liveDetector.detections.count < 6 {
                Text("可点“拍照识别”，失败后进入微调框")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
            }

            if shouldShowTorchHint {
                HStack(spacing: 8) {
                    Text("光线偏暗，建议打开闪光灯")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    Spacer()
                    Button(cameraManager.isTorchOn && !uiTestFlags.lowLightHintCheck ? "关闭闪光灯" : "打开闪光灯") {
                        if uiTestFlags.lowLightHintCheck {
                            return
                        }
                        cameraManager.toggleTorch()
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
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
        VStack(spacing: 12) {
            Button(action: captureAndDetect) {
                HStack(spacing: 8) {
                    if isCapturingPhoto {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "camera.circle.fill")
                            .font(.title3)
                    }
                    Text(isCapturingPhoto ? "拍照中…" : "拍照识别")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.blue.opacity(0.9))
                .cornerRadius(14)
            }
            .disabled(isCapturingPhoto || processing || !isCameraReady)
            .opacity((isCapturingPhoto || processing || !isCameraReady) ? 0.7 : 1.0)
            .accessibilityLabel("拍照识别")
            .accessibilityHint("拍摄当前画面并进入自动检测与微调流程")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: 10)],
                spacing: 10
            ) {
                secondaryButton(
                    title: "相册选择",
                    symbolName: "photo.on.rectangle",
                    accessibilityHint: "从相册导入单张照片进行识别"
                ) {
                    showingPhotoPicker = true
                }

                secondaryButton(
                    title: "手动输入",
                    symbolName: "pencil.and.list.clipboard",
                    accessibilityHint: "手动选择六爻阴阳"
                ) {
                    showingManualInput = true
                }

                secondaryButton(
                    title: "模板中心",
                    symbolName: "square.stack.3d.up",
                    accessibilityHint: "管理当前识别模板"
                ) {
                    showingTemplateCenter = true
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func secondaryButton(
        title: String,
        symbolName: String,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 10)
                .background(Color.black.opacity(0.6))
                .cornerRadius(14)
        }
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
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
                            suggestedResults = []
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
                        .disabled(processing || dataStorage.activeProfile == nil)
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

    private func captureAndDetect() {
        guard !isCapturingPhoto else { return }
        guard isCameraAuthorized else {
            showAlert("相机权限未开启，请先授权")
            return
        }
        guard cameraManager.isSessionRunning else {
            showAlert("相机启动中，请稍后再试")
            return
        }

        isCapturingPhoto = true
        cameraManager.capturePhotoWithResult { image in
            defer { isCapturingPhoto = false }
            guard let image = image else {
                showAlert("拍照失败，请重试")
                return
            }

            let normalized = ImageProcessor.normalizeOrientation(image)
            let aligned = cropCapturedImageToPreviewVisibleArea(normalized) ?? normalized
            capturedImage = aligned
            detectedCoins = []
            debugMatchResults = []
            suggestedResults = []
            processImage()
        }
    }

    private func processImage() {
        runDetection(showConfirmAfterMatch: true)
    }

    private func runDetection(showConfirmAfterMatch: Bool) {
        guard dataStorage.activeProfile != nil else {
            showAlert("请先设置铜钱模板", openTemplateCenter: true)
            return
        }

        guard canUseCurrentTemplateForInference() else {
            return
        }

        guard let image = capturedImage else { return }
        let normalizedImage = ImageProcessor.normalizeOrientation(image)
        capturedImage = normalizedImage

        debugLog("start process image size=\(image.size.width)x\(image.size.height) orientation=\(image.imageOrientation.rawValue)")
        debugLog("normalized image size=\(normalizedImage.size.width)x\(normalizedImage.size.height) orientation=\(normalizedImage.imageOrientation.rawValue)")

        processing = true
        processingStage = "检测铜钱…"

        Task {
            await MainActor.run {
                debugMatchResults = []
                suggestedResults = []
            }

            let foundCoins = await detectCoinsForProcessing(in: normalizedImage)
            let validCoins = filterHighQualityDetections(foundCoins)
            debugLog("detected coins count=\(foundCoins.count)")

            await MainActor.run {
                detectedCoins = validCoins
            }
            #if DEBUG
            if debugSaveImages {
                saveDebugImages(original: normalizedImage, detections: foundCoins)
            }
            #endif

            if foundCoins.count != 6 {
                await MainActor.run {
                    processing = false
                    processingStage = nil
                    presentAdjustView(
                        for: normalizedImage,
                        detections: foundCoins,
                        reason: .notEnoughCoins
                    )
                }
                return
            }

            if validCoins.count != 6 {
                await MainActor.run {
                    processing = false
                    processingStage = nil
                    presentAdjustView(
                        for: normalizedImage,
                        detections: foundCoins,
                        reason: .qualityRejected
                    )
                }
                return
            }

            await MainActor.run {
                processingStage = "匹配模板…"
            }
            let matchResults = await matchDetectedCoins(for: validCoins)

            await MainActor.run {
                suggestedResults = matchResults
                debugMatchResults = matchResults
                processing = false
                processingStage = nil
            }

            await MainActor.run {
                guard !matchResults.isEmpty else {
                    presentAdjustView(
                        for: normalizedImage,
                        detections: validCoins,
                        reason: .reliabilityRejected
                    )
                    return
                }
                if isResultReady(matchResults), hasReliableResults(matchResults) {
                    if showConfirmAfterMatch {
                        detectedCoins = validCoins
                        showingConfirm = true
                    } else {
                        presentResults(matchResults, source: .photo)
                    }
                    return
                }
                presentAdjustView(
                    for: normalizedImage,
                    detections: validCoins,
                    reason: .reliabilityRejected
                )
            }
        }
    }

    private func rerunDetectionWithAdjustedDrafts(
        _ drafts: [DetectionDraft],
        showConfirmAfterMatch: Bool
    ) {
        guard canUseCurrentTemplateForInference() else { return }
        guard let image = capturedImage else { return }
        let normalizedImage = ImageProcessor.normalizeOrientation(image)
        capturedImage = normalizedImage

        processing = true
        processingStage = "重新识别…"

        Task {
            let adjustedDetections = ROICropper.detections(from: drafts, image: normalizedImage)
            let validCoins = filterHighQualityDetections(adjustedDetections)
            let coinsForMatch: [CoinDetector.DetectedCoin]

            if adjustedDetections.count == 6 {
                coinsForMatch = validCoins.count == 6 ? validCoins : adjustedDetections
            } else {
                coinsForMatch = validCoins
            }

            await MainActor.run {
                detectedCoins = coinsForMatch
            }

            guard adjustedDetections.count == 6 else {
                await MainActor.run {
                    processing = false
                    processingStage = nil
                    presentAdjustView(
                        for: normalizedImage,
                        detections: adjustedDetections,
                        reason: .qualityRejected
                    )
                }
                return
            }

            await MainActor.run {
                processingStage = "匹配模板…"
            }
            let matchResults = await matchDetectedCoins(for: coinsForMatch)

            await MainActor.run {
                let confirmFriendlyResults = adjustedConfirmationResults(
                    from: matchResults,
                    detections: coinsForMatch
                )
                suggestedResults = confirmFriendlyResults
                debugMatchResults = confirmFriendlyResults
                processing = false
                processingStage = nil
            }

            await MainActor.run {
                let confirmFriendlyResults = adjustedConfirmationResults(
                    from: matchResults,
                    detections: coinsForMatch
                )
                if shouldEnterConfirmAfterAdjustment(confirmFriendlyResults) {
                    if showConfirmAfterMatch {
                        detectedCoins = coinsForMatch
                        showingConfirm = true
                    } else {
                        presentResults(confirmFriendlyResults, source: .photo)
                    }
                    return
                }
                presentAdjustView(
                    for: normalizedImage,
                    detections: coinsForMatch,
                    reason: .reliabilityRejected
                )
            }
        }
    }

    private func detectCoinsForProcessing(in image: UIImage) async -> [CoinDetector.DetectedCoin] {
        if !isAutoDetectionFlowEnabled {
            return ROICropper.slotDetections(for: image, in: previewSize)
        }

        if isStrictSlotGuidedDetectionEnabled {
            let slotGuided = await detectCoinsWithinSlotGuides(in: image)
            debugLog("strict slot guided detections count=\(slotGuided.count)")
            return slotGuided
        }

        let guideRegion = slotGuideRegionNormalized(in: image)
        if let guideRegion {
            debugLog(
                String(
                    format: "slot guide region x=%.3f y=%.3f w=%.3f h=%.3f",
                    guideRegion.origin.x,
                    guideRegion.origin.y,
                    guideRegion.width,
                    guideRegion.height
                )
            )
        }
        let guided = await CoinDetector.detectCoins(
            from: image,
            focusRegionNormalized: guideRegion
        )
        if !guided.isEmpty {
            return guided
        }

        return await CoinDetector.detectCoins(from: image, focusRegionNormalized: nil)
    }

    private func cropCapturedImageToPreviewVisibleArea(_ image: UIImage) -> UIImage? {
        guard previewSize.width > 0, previewSize.height > 0 else { return nil }
        guard let cgImage = image.cgImage else { return nil }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let viewRect = CGRect(origin: .zero, size: previewSize)
        let bounds = CGRect(origin: .zero, size: imageSize)
        let cropRect = ROICropper.mapViewRectToImageRect(
            viewRect,
            viewSize: previewSize,
            imageSize: imageSize
        ).integral.intersection(bounds)

        guard cropRect.width > 0, cropRect.height > 0 else { return nil }
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        debugLog(
            String(
                format: "capture aligned crop x=%.1f y=%.1f w=%.1f h=%.1f",
                cropRect.origin.x,
                cropRect.origin.y,
                cropRect.width,
                cropRect.height
            )
        )
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    private func detectCoinsWithinSlotGuides(
        in image: UIImage
    ) async -> [CoinDetector.DetectedCoin] {
        guard previewSize.width > 0, previewSize.height > 0 else { return [] }
        guard let cgImage = image.cgImage else { return [] }
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let bounds = CGRect(origin: .zero, size: imageSize)
        let baseSlots = ROICropper.slotDetections(
            for: image,
            in: previewSize,
            insetRatio: 0.03
        )
        guard !baseSlots.isEmpty else { return [] }
        let sortedSlots = baseSlots.sorted(by: { $0.position > $1.position })
        let slotRects = sortedSlots.map(\.rect).filter { $0.width > 0 && $0.height > 0 }
        guard !slotRects.isEmpty else { return [] }
        let averageSide = slotRects.reduce(0) { $0 + min($1.width, $1.height) } / CGFloat(slotRects.count)

        var columnRect = slotRects.reduce(CGRect.null) { partial, rect in
            partial.isNull ? rect : partial.union(rect)
        }
        let horizontalPad = averageSide * 0.16
        let verticalPad = averageSide * 0.10
        columnRect = columnRect
            .insetBy(dx: -horizontalPad, dy: -verticalPad)
            .integral
            .intersection(bounds)

        guard columnRect.width > 0,
              columnRect.height > 0,
              let columnCG = cgImage.cropping(to: columnRect) else {
            return sortedSlots
        }
        let columnBounds = CGRect(origin: .zero, size: CGSize(width: columnCG.width, height: columnCG.height))
        debugLog(
            String(
                format: "slot column crop x=%.1f y=%.1f w=%.1f h=%.1f",
                columnRect.origin.x,
                columnRect.origin.y,
                columnRect.width,
                columnRect.height
            )
        )

        var detections: [CoinDetector.DetectedCoin] = []
        detections.reserveCapacity(6)

        for slot in sortedSlots {
            let slotRect = slot.rect.integral.intersection(bounds)
            let localSlotRect = slotRect
                .offsetBy(dx: -columnRect.origin.x, dy: -columnRect.origin.y)
                .integral
                .intersection(columnBounds)
            guard localSlotRect.width > 0,
                  localSlotRect.height > 0,
                  let slotPatchCG = columnCG.cropping(to: localSlotRect) else {
                continue
            }
            let slotPatch = UIImage(cgImage: slotPatchCG)
            let targetSide = max(1, min(slotRect.width, slotRect.height) * 0.88)

            if let local = await CoinDetector.detectSingleCoinFast(from: slotPatch) {
                let localCenter = CGPoint(x: local.rect.midX, y: local.rect.midY)
                let globalCenter = CGPoint(
                    x: columnRect.origin.x + localSlotRect.origin.x + localCenter.x,
                    y: columnRect.origin.y + localSlotRect.origin.y + localCenter.y
                )
                let clampedContainer = slotRect.intersection(bounds)
                let globalRect = squareRect(
                    centeredAt: globalCenter,
                    side: targetSide,
                    inside: clampedContainer
                )
                guard globalRect.width > 0, globalRect.height > 0 else { continue }

                guard let rawGlobal = cgImage.cropping(to: globalRect) else { continue }
                let rawGlobalImage = UIImage(cgImage: rawGlobal)
                let normalizedRect = CGRect(
                    x: globalRect.origin.x / imageSize.width,
                    y: globalRect.origin.y / imageSize.height,
                    width: globalRect.width / imageSize.width,
                    height: globalRect.height / imageSize.height
                )

                detections.append(
                    CoinDetector.DetectedCoin(
                        image: rawGlobalImage,
                        maskedImage: ImageProcessor.applyCircularMask(rawGlobalImage),
                        position: slot.position,
                        rect: globalRect,
                        normalizedRect: normalizedRect
                    )
                )
                debugLog(
                    String(
                        format: "slot %d local detected -> rect x=%.1f y=%.1f w=%.1f h=%.1f",
                        slot.position,
                        globalRect.origin.x,
                        globalRect.origin.y,
                        globalRect.width,
                        globalRect.height
                    )
                )
                continue
            }

            let fallbackRect = squareRect(
                centeredAt: CGPoint(x: slotRect.midX, y: slotRect.midY),
                side: targetSide,
                inside: slotRect.intersection(bounds)
            )
            guard fallbackRect.width > 0, fallbackRect.height > 0 else { continue }
            guard let fallbackCrop = cgImage.cropping(to: fallbackRect) else { continue }
            let fallbackImage = UIImage(cgImage: fallbackCrop)
            let normalizedRect = CGRect(
                x: fallbackRect.origin.x / imageSize.width,
                y: fallbackRect.origin.y / imageSize.height,
                width: fallbackRect.width / imageSize.width,
                height: fallbackRect.height / imageSize.height
            )
            detections.append(
                CoinDetector.DetectedCoin(
                    image: fallbackImage,
                    maskedImage: ImageProcessor.applyCircularMask(fallbackImage),
                    position: slot.position,
                    rect: fallbackRect,
                    normalizedRect: normalizedRect
                )
            )
            debugLog(
                String(
                    format: "slot %d fallback rect x=%.1f y=%.1f w=%.1f h=%.1f",
                    slot.position,
                    fallbackRect.origin.x,
                    fallbackRect.origin.y,
                    fallbackRect.width,
                    fallbackRect.height
                )
            )
        }

        return detections.sorted { $0.position > $1.position }
    }

    private func squareRect(
        centeredAt center: CGPoint,
        side: CGFloat,
        inside bounds: CGRect
    ) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let finalSide = max(1, min(side, min(bounds.width, bounds.height)))
        var originX = center.x - finalSide / 2
        var originY = center.y - finalSide / 2
        originX = min(max(originX, bounds.minX), bounds.maxX - finalSide)
        originY = min(max(originY, bounds.minY), bounds.maxY - finalSide)
        return CGRect(x: originX, y: originY, width: finalSide, height: finalSide).integral
    }

    private func slotGuideRegionNormalized(in image: UIImage) -> CGRect? {
        guard previewSize.width > 0, previewSize.height > 0 else { return nil }
        guard let cgImage = image.cgImage else { return nil }

        let layout = SlotLayout.layoutNormalized(in: previewSize)
        var viewRect = layout.columnRect
        guard viewRect.width > 0, viewRect.height > 0 else { return nil }

        // Expand guide region to tolerate slight user misalignment while
        // still constraining detection to the slot column.
        viewRect = viewRect.insetBy(
            dx: -(viewRect.width * 0.55),
            dy: -(viewRect.height * 0.05)
        )
        let imageRect = ROICropper.mapViewRectToImageRect(
            viewRect,
            viewSize: previewSize,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height)
        )
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }

        let normalized = CGRect(
            x: imageRect.origin.x / CGFloat(cgImage.width),
            y: imageRect.origin.y / CGFloat(cgImage.height),
            width: imageRect.width / CGFloat(cgImage.width),
            height: imageRect.height / CGFloat(cgImage.height)
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard normalized.width > 0, normalized.height > 0 else { return nil }
        return normalized
    }

    private func filterHighQualityDetections(
        _ detections: [CoinDetector.DetectedCoin]
    ) -> [CoinDetector.DetectedCoin] {
        let presenceCalibration = ImageProcessor.CoinPresenceCalibration.default
        let qualityCalibration = ImageProcessor.CoinQualityCalibration.default

        return detections.filter { detection in
            let presenceScales: [CGFloat] = [1.0]
            var isPresent = false
            var isQualityPass = false
            var lastMetrics: ImageProcessor.CoinPresenceMetrics?

            for scale in presenceScales {
                let candidate = scale >= 0.999
                    ? detection.image
                    : ImageProcessor.centerCrop(detection.image, scale: scale)
                guard let metrics = ImageProcessor.coinPresenceMetrics(
                    for: candidate,
                    calibration: presenceCalibration
                ) else {
                    continue
                }
                lastMetrics = metrics
                if metrics.isPresent {
                    isPresent = true
                }
                if ImageProcessor.isCoinHighQualityForSlot(
                    position: detection.position,
                    energyMean: metrics.energyMean,
                    ringRatio: metrics.ringRatio,
                    centroidOffset: metrics.centroidOffset,
                    calibration: qualityCalibration
                ) {
                    isQualityPass = true
                }
            }

            #if DEBUG
            if (!isPresent || !isQualityPass), let metrics = lastMetrics {
                let label = isPresent ? "PhotoQualityReject" : "PhotoPresence"
                print(
                    String(
                        format: "%@: pos=%d energy=%.3f ring=%.3f offset=%.3f quality=%.3f",
                        label,
                        detection.position,
                        metrics.energyMean,
                        metrics.ringRatio,
                        metrics.centroidOffset,
                        metrics.qualityScore
                    )
                )
            }
            #endif

            return isQualityPass
        }
    }

    private func canUseCurrentTemplateForInference() -> Bool {
        guard let profile = dataStorage.activeProfile else {
            showAlert("请先设置铜钱模板", openTemplateCenter: true)
            return false
        }
        guard let frontData = TemplateManager.deserializeTemplateData(profile.frontTemplates),
              let backData = TemplateManager.deserializeTemplateData(profile.backTemplates) else {
            showAlert("模板数据异常，请重新设置", openTemplateCenter: true)
            return false
        }

        let frontTemplates = frontData.getObservations()
        let backTemplates = backData.getObservations()
        let hasDescriptors = !frontData.getDescriptors().isEmpty
            && !backData.getDescriptors().isEmpty
        let requiresUpgrade = frontData.version < 2
            || backData.version < 2
            || frontTemplates.isEmpty
            || backTemplates.isEmpty
            || !hasDescriptors

        guard !requiresUpgrade else {
            showAlert("模板版本过旧，请重录模板后再识别", openTemplateCenter: true)
            return false
        }
        return true
    }

    private func presentAdjustView(
        for image: UIImage,
        detections: [CoinDetector.DetectedCoin],
        reason: DetectionFailureReason
    ) {
        adjustmentReason = reason
        adjustmentDrafts = makeAdjustmentDrafts(
            for: detections,
            imageSize: image.size
        )
        if adjustmentDrafts.count == 6 {
            detectedCoins = ROICropper.detections(from: adjustmentDrafts, image: image)
        }
        showingAdjust = true
    }

    private func makeAdjustmentDrafts(
        for detections: [CoinDetector.DetectedCoin],
        imageSize: CGSize
    ) -> [DetectionDraft] {
        var drafts = ROICropper.drafts(from: detections)
        let fallbackDrafts = ROICropper.defaultDrafts(in: imageSize)
        if drafts.count < 6 {
            for fallback in fallbackDrafts where drafts.count < 6 {
                let duplicated = drafts.contains { draft in
                    let dx = draft.centerNormalized.x - fallback.centerNormalized.x
                    let dy = draft.centerNormalized.y - fallback.centerNormalized.y
                    return hypot(dx, dy) < 0.08
                }
                if !duplicated {
                    drafts.append(fallback)
                }
            }

            for fallback in fallbackDrafts where drafts.count < 6 {
                drafts.append(fallback)
            }
        }

        if drafts.isEmpty {
            drafts = fallbackDrafts
        }

        let sixDrafts = Array(drafts.prefix(6))
        return normalizeDraftSizesForAdjustment(
            sixDrafts,
            fallbackDrafts: fallbackDrafts,
            imageSize: imageSize
        )
    }

    private func normalizeDraftSizesForAdjustment(
        _ drafts: [DetectionDraft],
        fallbackDrafts: [DetectionDraft],
        imageSize: CGSize
    ) -> [DetectionDraft] {
        guard !drafts.isEmpty, imageSize.width > 0, imageSize.height > 0 else { return drafts }

        let draftPixelSides = drafts
            .map { max($0.sizeNormalized.width * imageSize.width, $0.sizeNormalized.height * imageSize.height) }
            .filter { $0 > 12 }
        let fallbackPixelSides = fallbackDrafts
            .map { max($0.sizeNormalized.width * imageSize.width, $0.sizeNormalized.height * imageSize.height) }
            .filter { $0 > 12 }

        let baseFallbackSide = medianValue(of: fallbackPixelSides) ?? min(imageSize.width, imageSize.height) * 0.22
        let baseDetectedSide = medianValue(of: draftPixelSides) ?? baseFallbackSide
        let boundedSide = min(max(baseDetectedSide, baseFallbackSide * 0.85), baseFallbackSide * 1.20)
        let minSide = min(imageSize.width, imageSize.height) * 0.10
        let maxSide = min(imageSize.width, imageSize.height) * 0.42
        let sidePixels = min(max(boundedSide, minSide), maxSide)
        let normalizedWidth = sidePixels / imageSize.width
        let normalizedHeight = sidePixels / imageSize.height
        let normalizedSize = CGSize(width: normalizedWidth, height: normalizedHeight)
        let halfWidth = normalizedWidth / 2
        let halfHeight = normalizedHeight / 2

        return drafts.map { draft in
            var adjusted = draft
            var center = adjusted.centerNormalized
            center.x = min(max(center.x, halfWidth), 1 - halfWidth)
            center.y = min(max(center.y, halfHeight), 1 - halfHeight)
            adjusted.centerNormalized = center
            adjusted.sizeNormalized = normalizedSize
            return adjusted
        }
    }

    private func medianValue(of values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private func showAlert(
        _ message: String,
        openTemplateCenter: Bool = false
    ) {
        errorMessage = message
        shouldOpenTemplateCenterAfterAlert = openTemplateCenter
        showingAlert = true
    }

    private func presentResults(_ results: [CoinResult], source: SessionSource) {
        guard !autoPresenting else { return }
        autoPresenting = true
        defer { autoPresenting = false }

        guard let profile = dataStorage.activeProfile else {
            showAlert("请先设置铜钱模板", openTemplateCenter: true)
            return
        }

        let _ = dataStorage.createSession(
            source: source,
            profileId: profile.id,
            results: results
        )

        resultYaos = results
            .sorted { $0.position < $1.position }
            .map(\.yinYang)
        capturedImage = nil
        detectedCoins = []
        debugMatchResults = []
        suggestedResults = []
        showingResult = true
    }

    private func handleConfirm(results: [CoinResult]) {
        let detectionsSnapshot = detectedCoins
        let profileIdSnapshot = dataStorage.activeProfile?.id
        let suggestionsSnapshot = suggestedResults
        showingConfirm = false

        if let profileIdSnapshot {
            Task {
                await ingestConfirmedSamples(
                    results: results,
                    detections: detectionsSnapshot,
                    profileId: profileIdSnapshot,
                    suggestions: suggestionsSnapshot
                )
            }
        }

        presentResults(results, source: capturedImage == nil ? .camera : .photo)
    }

    private func ingestConfirmedSamples(
        results: [CoinResult],
        detections: [CoinDetector.DetectedCoin],
        profileId: UUID,
        suggestions: [CoinResult]
    ) async {
        guard !results.isEmpty, !detections.isEmpty else { return }
        let sideByPosition = Dictionary(uniqueKeysWithValues: results.map { ($0.position, $0.side) })
        let suggestionByPosition = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.position, $0) })

        var frontImages: [UIImage] = []
        var backImages: [UIImage] = []
        var skippedForLowConfidence = 0
        for detection in detections {
            guard let side = sideByPosition[detection.position] else { continue }
            guard let suggestion = suggestionByPosition[detection.position] else { continue }
            guard (suggestion.side == .front || suggestion.side == .back),
                  suggestion.side == side,
                  suggestion.confidence >= 0.72 else {
                skippedForLowConfidence += 1
                continue
            }
            let source = detection.maskedImage ?? detection.image
            switch side {
            case .front:
                frontImages.append(source)
            case .back:
                backImages.append(source)
            case .uncertain, .invalid:
                continue
            }
        }

        guard !frontImages.isEmpty || !backImages.isEmpty else { return }

        let context: (
            profile: CoinProfile,
            frontData: TemplateManager.TemplateData,
            backData: TemplateManager.TemplateData
        )? = await MainActor.run {
            guard let profile = dataStorage.profiles.first(where: { $0.id == profileId }),
                  let frontData = TemplateManager.deserializeTemplateData(profile.frontTemplates),
                  let backData = TemplateManager.deserializeTemplateData(profile.backTemplates) else {
                return nil
            }
            return (profile, frontData, backData)
        }

        guard let context else { return }

        let updatedFront = frontImages.isEmpty
            ? context.frontData
            : await TemplateManager.appendingSamples(
                to: context.frontData,
                images: frontImages,
                maxSampleCount: 120
            )
        let updatedBack = backImages.isEmpty
            ? context.backData
            : await TemplateManager.appendingSamples(
                to: context.backData,
                images: backImages,
                maxSampleCount: 120
            )

        guard let frontEncoded = TemplateManager.serializeTemplateData(updatedFront),
              let backEncoded = TemplateManager.serializeTemplateData(updatedBack) else {
            return
        }

        await MainActor.run {
            guard var latest = dataStorage.profiles.first(where: { $0.id == profileId }) else {
                return
            }
            latest.frontTemplates = frontEncoded
            latest.backTemplates = backEncoded
            dataStorage.updateProfile(latest)
            textCalibrationCache[profileId] = nil
        }

        debugLog(
            "learned samples front+=\(frontImages.count) back+=\(backImages.count) skipped=\(skippedForLowConfidence)"
        )
    }

    private func isResultReady(_ results: [CoinResult]) -> Bool {
        guard results.count == 6 else { return false }
        let positions = Set(results.map { $0.position })
        return positions.count == 6
    }

    private func hasReliableResults(_ results: [CoinResult]) -> Bool {
        ResultReliabilityEvaluator.isReliable(results)
    }

    private func hasAdjustedFlowReliability(_ results: [CoinResult]) -> Bool {
        let calibration = ResultReliabilityEvaluator.Calibration(
            minPerCoinConfidence: 0.52,
            minAverageConfidence: 0.60,
            maxLowConfidenceCount: 2
        )
        return ResultReliabilityEvaluator.isReliable(results, calibration: calibration)
    }

    private func adjustedConfirmationResults(
        from matchResults: [CoinResult],
        detections: [CoinDetector.DetectedCoin]
    ) -> [CoinResult] {
        if isResultReady(matchResults) {
            return matchResults.map { result in
                guard result.side == .invalid else { return result }
                var fallback = result
                fallback.side = .uncertain
                fallback.yinYang = .yang
                fallback.confidence = max(0.35, min(result.confidence, 0.49))
                return fallback
            }
        }

        guard detections.count == 6 else { return matchResults }
        return detections.map { detection in
            CoinResult(
                position: detection.position,
                yinYang: .yang,
                side: .uncertain,
                confidence: 0.35
            )
        }
    }

    private func shouldEnterConfirmAfterAdjustment(_ results: [CoinResult]) -> Bool {
        guard isResultReady(results) else { return false }
        if hasReliableResults(results) || hasAdjustedFlowReliability(results) {
            return true
        }
        // After manual box adjustment, allow user to finalize on confirm page
        // as long as each coin has a non-invalid placeholder decision.
        return results.allSatisfy { $0.side != .invalid }
    }

    private func matchDetectedCoins(for detections: [CoinDetector.DetectedCoin]) async -> [CoinResult] {
        let profile: CoinProfile? = await MainActor.run { dataStorage.activeProfile }
        guard let profile = profile else { return [] }
        guard let frontData = TemplateManager.deserializeTemplateData(profile.frontTemplates),
              let backData = TemplateManager.deserializeTemplateData(profile.backTemplates) else {
            await MainActor.run {
                showAlert("模板数据异常，请重新设置", openTemplateCenter: true)
            }
            return []
        }

        let frontTemplates = frontData.getObservations()
        let backTemplates = backData.getObservations()
        let frontDescriptors = frontData.getDescriptors()
        let backDescriptors = backData.getDescriptors()
        let requiresUpgrade = frontData.version < 2
            || backData.version < 2
            || frontTemplates.isEmpty
            || backTemplates.isEmpty
        if requiresUpgrade {
            await MainActor.run {
                showAlert("模板版本过旧，请重录模板后再识别", openTemplateCenter: true)
            }
            return []
        }
        if frontDescriptors.isEmpty || backDescriptors.isEmpty {
            await MainActor.run {
                showAlert("模板数据不完整，请重录模板后再识别", openTemplateCenter: true)
            }
            return []
        }
        let ringPair = await resolveRingDescriptors(
            profile: profile,
            frontData: frontData,
            backData: backData
        )
        let frontRingDescriptors = ringPair.front
        let backRingDescriptors = ringPair.back
        let calibration = ConfidenceCalculator.calibrate(
            frontTemplates: frontTemplates,
            backTemplates: backTemplates
        )
        let descriptorCalibration = FeatureMatchService.calibrateDescriptors(
            frontDescriptors: frontDescriptors,
            backDescriptors: backDescriptors
        )
        let ringCalibration = FeatureMatchService.calibrateRingDescriptors(
            frontDescriptors: frontRingDescriptors,
            backDescriptors: backRingDescriptors
        )
        let textCalibration = await resolveTextCalibration(profile: profile)

        let roiCandidates = await buildROICandidates(from: detections)

        let results = await FeatureMatchService.matchAllCoinCandidates(
            roiCandidates: roiCandidates,
            frontTemplates: frontTemplates,
            backTemplates: backTemplates,
            calibration: calibration,
            frontDescriptors: frontDescriptors,
            backDescriptors: backDescriptors,
            descriptorCalibration: descriptorCalibration,
            frontRingDescriptors: frontRingDescriptors,
            backRingDescriptors: backRingDescriptors,
            ringCalibration: ringCalibration,
            textCalibration: textCalibration
        )
        return results
    }

    private func buildROICandidates(
        from detections: [CoinDetector.DetectedCoin]
    ) async -> [(Int, [UIImage])] {
        var roiCandidates: [(Int, [UIImage])] = []
        roiCandidates.reserveCapacity(detections.count)

        for detection in detections {
            let candidates = await refinedCandidates(for: detection)
            roiCandidates.append((detection.position, candidates))
        }

        return roiCandidates
    }

    private func refinedCandidates(
        for detection: CoinDetector.DetectedCoin
    ) async -> [UIImage] {
        var seeds: [UIImage] = []
        if let masked = detection.maskedImage {
            seeds.append(masked)
        }
        seeds.append(detection.image)

        var refinedSources: [UIImage] = []
        refinedSources.reserveCapacity(seeds.count)
        for seed in seeds {
            if let recentered = await CoinDetector.detectSingleCoinFast(from: seed) {
                refinedSources.append(recentered.maskedImage ?? recentered.image)
            } else {
                refinedSources.append(seed)
            }
        }

        let zoomScales: [CGFloat] = [1.0, 0.90, 0.80, 0.70]
        var candidates: [UIImage] = []
        candidates.reserveCapacity(refinedSources.count * 8)

        for source in refinedSources {
            let zoomed = ImageProcessor.zoomedVariants(for: source, scales: zoomScales)
            candidates.append(contentsOf: zoomed)

            let normalized = ImageProcessor.prepareCoinForMatching(source)
            candidates.append(normalized)
            candidates.append(ImageProcessor.applyColorControls(normalized, contrast: 1.15, brightness: 0.02))
            candidates.append(ImageProcessor.applyColorControls(normalized, contrast: 0.90, brightness: -0.03))
        }

        if candidates.isEmpty {
            return [detection.maskedImage ?? detection.image]
        }
        return Array(candidates.prefix(14))
    }

    private func resolveRingDescriptors(
        profile: CoinProfile,
        frontData: TemplateManager.TemplateData,
        backData: TemplateManager.TemplateData
    ) async -> (front: [[Float]], back: [[Float]]) {
        var frontRing = frontData.getRingDescriptors()
        var backRing = backData.getRingDescriptors()

        guard frontRing.isEmpty || backRing.isEmpty else {
            return (frontRing, backRing)
        }

        let frontImages = profile.frontPreviewImages.compactMap { UIImage(data: $0) }
        let backImages = profile.backPreviewImages.compactMap { UIImage(data: $0) }

        if frontRing.isEmpty, !frontImages.isEmpty {
            frontRing = await TemplateManager.createRingDescriptors(from: frontImages, useCoinDetection: true)
        }
        if backRing.isEmpty, !backImages.isEmpty {
            backRing = await TemplateManager.createRingDescriptors(from: backImages, useCoinDetection: true)
        }

        if frontRing.isEmpty || backRing.isEmpty {
            return (frontRing, backRing)
        }

        let patchedFront = TemplateManager.attachingRingDescriptors(
            to: frontData,
            ringDescriptors: frontRing
        )
        let patchedBack = TemplateManager.attachingRingDescriptors(
            to: backData,
            ringDescriptors: backRing
        )

        guard let frontEncoded = TemplateManager.serializeTemplateData(patchedFront),
              let backEncoded = TemplateManager.serializeTemplateData(patchedBack) else {
            return (frontRing, backRing)
        }

        await MainActor.run {
            guard var latest = dataStorage.profiles.first(where: { $0.id == profile.id }) else {
                return
            }
            latest.frontTemplates = frontEncoded
            latest.backTemplates = backEncoded
            dataStorage.updateProfile(latest)
        }
        debugLog("auto patched ring descriptors front=\(frontRing.count) back=\(backRing.count)")

        return (frontRing, backRing)
    }

    private func resolveTextCalibration(
        profile: CoinProfile
    ) async -> FeatureMatchService.TextCalibration {
        if let cached = await MainActor.run(body: { textCalibrationCache[profile.id] }) {
            return cached
        }

        let frontImages = profile.frontPreviewImages.compactMap { UIImage(data: $0) }
        let backImages = profile.backPreviewImages.compactMap { UIImage(data: $0) }
        let calibration = await FeatureMatchService.calibrateText(
            frontImages: frontImages,
            backImages: backImages
        )

        await MainActor.run {
            textCalibrationCache[profile.id] = calibration
        }
        debugLog(
            "text calibration enabled=\(calibration.enabled) frontMean=\(String(format: "%.3f", calibration.frontMean)) backMean=\(String(format: "%.3f", calibration.backMean))"
        )
        return calibration
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

    private func updateLiveDetectionState() {
        let shouldEnable = capturedImage == nil && !showingResult && !showingConfirm && !showingAdjust
        liveDetector.setEnabled(shouldEnable)
    }

    private func updatePreviewSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if previewSize != size {
            previewSize = size
            liveDetector.setPreviewSize(size)
        }
    }

    private func scheduleAlignHintDismissal() {
        showAlignHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                showAlignHint = false
            }
        }
    }

    private func injectMockConfirmIfNeeded() {
        #if DEBUG
        guard uiTestFlags.mockUncertainConfirm else { return }
        guard capturedImage == nil, !showingResult, !showingConfirm else { return }

        let baseImage = makeMockCoinImage(size: CGSize(width: 120, height: 120))
        let detections = (1...6).map { position in
            CoinDetector.DetectedCoin(
                image: baseImage,
                maskedImage: ImageProcessor.applyCircularMask(baseImage),
                position: position,
                rect: CGRect(x: 0, y: 0, width: 120, height: 120),
                normalizedRect: CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
            )
        }
        let results = (1...6).map { position in
            CoinResult(
                position: position,
                yinYang: .yang,
                side: position % 2 == 0 ? .uncertain : .back,
                confidence: 0.5
            )
        }

        guard isResultReady(results) else { return }
        detectedCoins = detections
        suggestedResults = results
        debugMatchResults = results
        showingConfirm = true
        #endif
    }

    private func makeMockCoinImage(size: CGSize) -> UIImage {
        #if DEBUG
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor(white: 0.85, alpha: 1).setFill()
            context.fill(bounds)

            UIColor(white: 0.25, alpha: 1).setStroke()
            context.cgContext.setLineWidth(6)
            context.cgContext.strokeEllipse(in: bounds.insetBy(dx: 10, dy: 10))

            UIColor(white: 0.45, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: bounds.insetBy(dx: 44, dy: 44))
        }
        #else
        UIImage()
        #endif
    }
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

private struct CameraViewUITestFlags {
    let mockUncertainConfirm: Bool
    let layoutCheck: Bool
    let presenceCheck: Bool
    let qualityCheck: Bool
    let stabilityCheck: Bool
    let matchCheck: Bool
    let reliabilityCheck: Bool
    let lowLightHintCheck: Bool
    let forceLegacyDetection: Bool

    var shouldBypassTemplateRequirement: Bool {
        mockUncertainConfirm || layoutCheck || presenceCheck || qualityCheck || stabilityCheck || matchCheck || reliabilityCheck || lowLightHintCheck
    }

    static var current: CameraViewUITestFlags {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return CameraViewUITestFlags(
            mockUncertainConfirm: args.contains("-ui-testing-mock-confirm-uncertain"),
            layoutCheck: args.contains("-ui-testing-layout-check"),
            presenceCheck: args.contains("-ui-testing-presence-check"),
            qualityCheck: args.contains("-ui-testing-quality-check"),
            stabilityCheck: args.contains("-ui-testing-stability-check"),
            matchCheck: args.contains("-ui-testing-match-check"),
            reliabilityCheck: args.contains("-ui-testing-reliability-check"),
            lowLightHintCheck: args.contains("-ui-testing-low-light-hint-check"),
            forceLegacyDetection: args.contains("-ui-testing-force-legacy-detection")
        )
        #else
        return CameraViewUITestFlags(
            mockUncertainConfirm: false,
            layoutCheck: false,
            presenceCheck: false,
            qualityCheck: false,
            stabilityCheck: false,
            matchCheck: false,
            reliabilityCheck: false,
            lowLightHintCheck: false,
            forceLegacyDetection: false
        )
        #endif
    }

    static func layoutStatusText(for previewSize: CGSize) -> String {
        #if DEBUG
        let probeSize = previewSize.width > 0 && previewSize.height > 0
            ? previewSize
            : UIScreen.main.bounds.size
        let layout = SlotLayout.layoutNormalized(in: probeSize)
        let insetTopRatio = layout.columnRect.minY / max(probeSize.height, 1)
        let insetBottomRatio = (probeSize.height - layout.columnRect.maxY) / max(probeSize.height, 1)
        let insetBalanced = abs(insetTopRatio - insetBottomRatio) <= 0.03
        let inExpectedRange = insetTopRatio >= 0.05 && insetTopRatio <= 0.13
        return insetBalanced && inExpectedRange ? "LAYOUT_OK" : "LAYOUT_BAD"
        #else
        return ""
        #endif
    }

    static func presenceStatusText() -> String {
        #if DEBUG
        let acceptsEdgeCase = ImageProcessor.isCoinPresent(energyMean: 0.19, ringRatio: 0.06)
        let acceptsLowRingEdge = ImageProcessor.isCoinPresent(energyMean: 0.18, ringRatio: 0.05)
        let rejectsLowEnergyNoise = !ImageProcessor.isCoinPresent(energyMean: 0.03, ringRatio: 0.03)
        let rejectsTooLowRing = !ImageProcessor.isCoinPresent(energyMean: 0.18, ringRatio: 0.02)
        let allChecksPass = acceptsEdgeCase && acceptsLowRingEdge && rejectsLowEnergyNoise && rejectsTooLowRing
        return allChecksPass ? "PRESENCE_OK" : "PRESENCE_BAD"
        #else
        return ""
        #endif
    }

    static func qualityStatusText() -> String {
        #if DEBUG
        let acceptsBalanced = ImageProcessor.isCoinHighQuality(
            energyMean: 0.11,
            ringRatio: 0.08,
            centroidOffset: 0.18
        )
        let rejectsLowRing = !ImageProcessor.isCoinHighQuality(
            energyMean: 0.11,
            ringRatio: 0.02,
            centroidOffset: 0.18
        )
        let rejectsOffset = !ImageProcessor.isCoinHighQuality(
            energyMean: 0.11,
            ringRatio: 0.08,
            centroidOffset: 0.72
        )
        let allChecksPass = acceptsBalanced && rejectsLowRing && rejectsOffset
        return allChecksPass ? "QUALITY_OK" : "QUALITY_BAD"
        #else
        return ""
        #endif
    }

    static func stabilityStatusText() -> String {
        #if DEBUG
        let required = 6
        var progress = 0
        progress = LiveDetectionController.nextStableFrameCount(current: progress, qualityReady: true, required: required)
        progress = LiveDetectionController.nextStableFrameCount(current: progress, qualityReady: true, required: required)
        progress = LiveDetectionController.nextStableFrameCount(current: progress, qualityReady: false, required: required)
        let resetWorks = progress == 0

        progress = LiveDetectionController.nextStableFrameCount(current: progress, qualityReady: true, required: required)
        progress = LiveDetectionController.nextStableFrameCount(current: progress, qualityReady: true, required: required)
        progress = LiveDetectionController.nextStableFrameCount(current: progress, qualityReady: true, required: required)
        progress = LiveDetectionController.nextStableFrameCount(current: progress, qualityReady: true, required: required)
        let lockWorks = progress == required

        return resetWorks && lockWorks ? "STABILITY_OK" : "STABILITY_BAD"
        #else
        return ""
        #endif
    }

    static func matchStatusText() -> String {
        #if DEBUG
        let calibration = FeatureMatchService.DescriptorCalibration.default
        let decisiveByGap = FeatureMatchService.classifyDescriptorScores(
            frontScore: 0.84,
            backScore: 0.77,
            calibration: calibration
        )
        let conflictLike = FeatureMatchService.classifyDescriptorScores(
            frontScore: 0.84,
            backScore: 0.81,
            calibration: calibration
        )
        let decisiveBack = FeatureMatchService.classifyDescriptorScores(
            frontScore: 0.60,
            backScore: 0.73,
            calibration: calibration
        )
        let weakNoise = FeatureMatchService.classifyDescriptorScores(
            frontScore: 0.44,
            backScore: 0.41,
            calibration: calibration
        )
        let consensusFront = FeatureMatchService.resolveCandidateEvidence(
            frontEvidence: 2.2,
            backEvidence: 0.7,
            frontCount: 3,
            backCount: 1
        )
        let consensusUncertain = FeatureMatchService.resolveCandidateEvidence(
            frontEvidence: 1.1,
            backEvidence: 1.0,
            frontCount: 1,
            backCount: 1
        )
        let smoothedDominant = CoinResultSmoother.resolveSmoothedScores(frontScore: 0.57, backScore: 0.43)

        let descriptorChecks =
            decisiveByGap.0 == .front &&
            conflictLike.0 == .uncertain &&
            decisiveBack.0 == .back &&
            weakNoise.0 == .invalid
        let consensusChecks = consensusFront.0 == .front && consensusUncertain.0 == .uncertain
        let smoothingChecks = smoothedDominant.0 == .front
        return descriptorChecks && consensusChecks && smoothingChecks ? "MATCH_OK" : "MATCH_BAD"
        #else
        return ""
        #endif
    }

    static func reliabilityStatusText() -> String {
        #if DEBUG
        let reliable = (1...6).map { position in
            CoinResult(
                position: position,
                yinYang: position % 2 == 0 ? .yin : .yang,
                side: position % 2 == 0 ? .front : .back,
                confidence: 0.78
            )
        }
        let unreliable = (1...6).map { position in
            CoinResult(
                position: position,
                yinYang: .yang,
                side: position == 3 ? .uncertain : .back,
                confidence: position == 5 ? 0.48 : 0.62
            )
        }
        let acceptsReliable = ResultReliabilityEvaluator.isReliable(reliable)
        let rejectsUnreliable = !ResultReliabilityEvaluator.isReliable(unreliable)
        return acceptsReliable && rejectsUnreliable ? "RELIABILITY_OK" : "RELIABILITY_BAD"
        #else
        return ""
        #endif
    }
}

#if DEBUG
struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
    }
}
#endif
