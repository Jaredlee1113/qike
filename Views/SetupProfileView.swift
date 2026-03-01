import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct SetupProfileView: View {
    @EnvironmentObject var dataStorage: DataStorageManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var profileName = ""
    @State private var frontTemplateImages: [UIImage] = []
    @State private var backTemplateImages: [UIImage] = []
    @State private var showingImagePicker = false
    @State private var pickerType: PickerType = .front
    @State private var errorMessage: String?
    @State private var alertTitle = "提示"
    @State private var showingAlert = false
    @State private var shouldDismissAfterAlert = false
    @State private var isSaving = false

    private let minimumTemplateCount = 3
    private let maximumTemplateCount = 5
    
    enum PickerType {
        case front
        case back
    }

    private var canSave: Bool {
        frontTemplateImages.count >= minimumTemplateCount &&
            backTemplateImages.count >= minimumTemplateCount &&
            !isSaving
    }

    private var frontRemainingSlots: Int {
        max(maximumTemplateCount - frontTemplateImages.count, 0)
    }

    private var backRemainingSlots: Int {
        max(maximumTemplateCount - backTemplateImages.count, 0)
    }
    
    var body: some View {
        Form {
            Section("铜钱配置") {
                TextField("配置名称", text: $profileName)
                    .textInputAutocapitalization(.words)
            }
            
            Section("字面模板 (阴面)") {
                HStack {
                    Text("模板数量: \(frontTemplateImages.count)/\(maximumTemplateCount)")
                    Text("至少 \(minimumTemplateCount) 张")
                        .font(.caption2)
                        .foregroundColor(frontTemplateImages.count >= minimumTemplateCount ? .green : .orange)
                    Spacer()
                    Button("添加") {
                        pickerType = .front
                        showingImagePicker = true
                    }
                    .disabled(frontTemplateImages.count >= maximumTemplateCount)
                }
                
                if !frontTemplateImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(0..<frontTemplateImages.count, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: frontTemplateImages[index])
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 80)
                                        .cornerRadius(8)
                                    
                                    Button(action: {
                                        frontTemplateImages.remove(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .accessibilityLabel("删除阴面模板\(index + 1)")
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
            }
            
            Section("图案面模板 (阳面)") {
                HStack {
                    Text("模板数量: \(backTemplateImages.count)/\(maximumTemplateCount)")
                    Text("至少 \(minimumTemplateCount) 张")
                        .font(.caption2)
                        .foregroundColor(backTemplateImages.count >= minimumTemplateCount ? .green : .orange)
                    Spacer()
                    Button("添加") {
                        pickerType = .back
                        showingImagePicker = true
                    }
                    .disabled(backTemplateImages.count >= maximumTemplateCount)
                }
                
                if !backTemplateImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(0..<backTemplateImages.count, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: backTemplateImages[index])
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 80)
                                        .cornerRadius(8)
                                    
                                    Button(action: {
                                        backTemplateImages.remove(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .accessibilityLabel("删除阳面模板\(index + 1)")
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
            }
            
            Section("提示") {
                Text("请为阴面和阳面各提供3-5张清晰照片。可一次多选，建议包含不同角度和光照条件，以提高识别准确度。若出现“不确定”，请调整光线或重新录入模板。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("设置铜钱模板")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
                .disabled(isSaving)
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveProfile()
                }
                .disabled(!canSave)
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                selectedImages: pickerType == .front ? $frontTemplateImages : $backTemplateImages,
                maxSelectionCount: pickerType == .front ? frontRemainingSlots : backRemainingSlots
            )
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("确定", role: .cancel) {
                if shouldDismissAfterAlert {
                    dismiss()
                }
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    ProgressView("生成模板中…")
                        .padding()
                        .background(Color.black.opacity(0.75))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
    }
    
    private func saveProfile() {
        guard !isSaving else { return }
        guard frontTemplateImages.count >= minimumTemplateCount,
              backTemplateImages.count >= minimumTemplateCount else {
            alertTitle = "提示"
            shouldDismissAfterAlert = false
            errorMessage = "请至少添加\(minimumTemplateCount)张阴面模板和\(minimumTemplateCount)张阳面模板"
            showingAlert = true
            return
        }
        isSaving = true

        let name = normalizedProfileName()
        profileName = name
        let frontImages = frontTemplateImages
        let backImages = backTemplateImages
        let frontPreviewImages = frontImages.compactMap(encodePreviewImageData)
        let backPreviewImages = backImages.compactMap(encodePreviewImageData)

        Task.detached(priority: .userInitiated) {
            let frontTemplateData = await TemplateManager.createTemplates(
                from: frontImages,
                includeFeaturePrints: true,
                useCoinDetection: true
            )
            let backTemplateData = await TemplateManager.createTemplates(
                from: backImages,
                includeFeaturePrints: true,
                useCoinDetection: true
            )
            let hasFrontTemplate = !frontTemplateData.descriptors.isEmpty || !frontTemplateData.featurePrints.isEmpty
            let hasBackTemplate = !backTemplateData.descriptors.isEmpty || !backTemplateData.featurePrints.isEmpty

            guard hasFrontTemplate, hasBackTemplate else {
                await MainActor.run {
                    alertTitle = "提示"
                    shouldDismissAfterAlert = false
                    errorMessage = "模板生成失败，请确保图片中有完整清晰的单枚铜钱"
                    showingAlert = true
                    isSaving = false
                }
                return
            }

            guard let frontData = TemplateManager.serializeTemplateData(frontTemplateData),
                  let backData = TemplateManager.serializeTemplateData(backTemplateData) else {
                await MainActor.run {
                    alertTitle = "提示"
                    shouldDismissAfterAlert = false
                    errorMessage = "模板生成失败"
                    showingAlert = true
                    isSaving = false
                }
                return
            }

            await MainActor.run {
                let _ = dataStorage.createProfile(
                    name: name,
                    frontTemplates: frontData,
                    backTemplates: backData,
                    frontPreviewImages: frontPreviewImages,
                    backPreviewImages: backPreviewImages
                )
                isSaving = false
                alertTitle = "保存成功"
                shouldDismissAfterAlert = true
                errorMessage = "模板已保存并设为当前模板"
                showingAlert = true
            }
        }
    }

    private func normalizedProfileName() -> String {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return defaultProfileName()
    }

    private func defaultProfileName() -> String {
        DateFormatter.templateNameFormatter.string(from: Date())
    }

    private func encodePreviewImageData(_ image: UIImage) -> Data? {
        let targetMaxDimension: CGFloat = 1024
        let resized = resizeIfNeeded(image, maxDimension: targetMaxDimension)
        return resized.jpegData(compressionQuality: 0.72)
    }

    private func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)
        guard longestEdge > maxDimension, longestEdge > 0 else { return image }

        let ratio = maxDimension / longestEdge
        let targetSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private extension DateFormatter {
    static let templateNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd HHmm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    let maxSelectionCount: Int
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = max(1, maxSelectionCount)
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
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            let cappedResults = Array(results.prefix(max(0, parent.maxSelectionCount)))
            guard !cappedResults.isEmpty else { return }

            for result in cappedResults {
                loadImage(from: result.itemProvider) { [weak self] image in
                    guard let self = self, let image = image else { return }
                    DispatchQueue.main.async {
                        self.parent.selectedImages.append(image)
                    }
                }
            }
        }

        private func loadImage(from itemProvider: NSItemProvider, completion: @escaping (UIImage?) -> Void) {
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                    if let error = error {
                        print("Error loading image: \(error.localizedDescription)")
                        completion(nil)
                        return
                    }
                    completion(image as? UIImage)
                }
                return
            }

            if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                    if let error = error {
                        print("Error loading image: \(error.localizedDescription)")
                        completion(nil)
                        return
                    }

                    if let data = item as? Data, let image = UIImage(data: data) {
                        completion(image)
                        return
                    }

                    if let url = item as? URL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        completion(image)
                        return
                    }

                    completion(nil)
                }
                return
            }

            print("Item provider doesn't conform to image type")
            completion(nil)
        }
    }
}

#if DEBUG
struct SetupProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SetupProfileView()
                .environmentObject(DataStorageManager.shared)
        }
    }
}
#endif
