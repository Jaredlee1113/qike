import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
    
    enum PickerType {
        case front
        case back
    }
    
    var body: some View {
        Form {
            Section("铜钱配置") {
                TextField("配置名称", text: $profileName)
                    .textInputAutocapitalization(.words)
            }
            
            Section("字面模板 (阴面)") {
                HStack {
                    Text("模板数量: \(frontTemplateImages.count)")
                    Spacer()
                    Button("添加") {
                        pickerType = .front
                        showingImagePicker = true
                    }
                    .disabled(frontTemplateImages.count >= 5)
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
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
            }
            
            Section("图案面模板 (阳面)") {
                HStack {
                    Text("模板数量: \(backTemplateImages.count)")
                    Spacer()
                    Button("添加") {
                        pickerType = .back
                        showingImagePicker = true
                    }
                    .disabled(backTemplateImages.count >= 5)
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
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
            }
            
            Section("提示") {
                Text("请提供3-5张铜钱正反面的清晰照片作为模板。模板照片建议在不同角度和光照下拍摄，以提高识别准确度。若出现“不确定”，请调整光线或重新录入模板。")
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
                .disabled(isSaving || frontTemplateImages.isEmpty || backTemplateImages.isEmpty)
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImages: pickerType == .front ? $frontTemplateImages : $backTemplateImages)
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
        guard !frontTemplateImages.isEmpty, !backTemplateImages.isEmpty else {
            alertTitle = "提示"
            shouldDismissAfterAlert = false
            errorMessage = "请先添加正反面模板"
            showingAlert = true
            return
        }
        isSaving = true

        let name = normalizedProfileName()
        profileName = name
        let frontImages = frontTemplateImages
        let backImages = backTemplateImages

        Task.detached(priority: .userInitiated) {
            let frontTemplateData = await TemplateManager.createTemplates(from: frontImages)
            let backTemplateData = await TemplateManager.createTemplates(from: backImages)
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
                dataStorage.createProfile(
                    name: name,
                    frontTemplates: frontData,
                    backTemplates: backData
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
    @Environment(\.dismiss) private var dismiss
    
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
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let result = results.first else { return }
            
            let itemProvider = result.itemProvider
            if itemProvider.canLoadObject(ofClass: UIImage.self) {
                itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("Error loading image: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let image = image as? UIImage else {
                        print("Loaded item is not a UIImage")
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.parent.selectedImages.append(image)
                        print("Successfully loaded image, total images: \(self.parent.selectedImages.count)")
                    }
                }
            } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("Error loading image: \(error.localizedDescription)")
                        return
                    }
                    
                    if let data = item as? Data, let image = UIImage(data: data) {
                        DispatchQueue.main.async {
                            self.parent.selectedImages.append(image)
                            print("Successfully loaded image, total images: \(self.parent.selectedImages.count)")
                        }
                    } else if let url = item as? URL {
                        // Try to load from URL if data approach fails
                        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                            DispatchQueue.main.async {
                                self.parent.selectedImages.append(image)
                                print("Successfully loaded image from URL, total images: \(self.parent.selectedImages.count)")
                            }
                        }
                    }
                }
            } else {
                print("Item provider doesn't conform to image type")
            }
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
