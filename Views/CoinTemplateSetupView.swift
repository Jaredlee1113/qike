import SwiftUI
import PhotosUI

// MARK: - 主视图
struct CoinTemplateSetupView: View {
    @EnvironmentObject var templateManager: CoinTemplateStorageManager
    @Environment(\.dismiss) private var dismiss

    @State private var templateName: String = ""
    @State private var frontPhotoPickerItem: PhotosPickerItem?
    @State private var backPhotoPickerItem: PhotosPickerItem?
    @State private var frontImage: UIImage?
    @State private var backImage: UIImage?
    @State private var showingDeleteAlert = false
    @State private var templateToDelete: CoinTemplate?
    @State private var showEmptyNameAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                newTemplateForm
                Divider().padding(.horizontal, 16)
                templateListSection
            }
        }
        .navigationTitle("模板设置")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: frontPhotoPickerItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    frontImage = uiImage
                }
            }
        }
        .onChange(of: backPhotoPickerItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    backImage = uiImage
                }
            }
        }
        .alert("请输入模板名称", isPresented: $showEmptyNameAlert) {
            Button("确定", role: .cancel) { }
        }
        .alert("删除模板", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                if let template = templateToDelete {
                    templateManager.deleteTemplate(template)
                    templateToDelete = nil
                }
            }
        } message: {
            Text("确定要删除这个模板吗？")
        }
    }

    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("铜钱模板设置")
                .font(.title2)
                .fontWeight(.bold)
            Text("上传铜钱正反面照片作为模板")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }

    private var newTemplateForm: some View {
        VStack(spacing: 16) {
            TemplateNameField(name: $templateName)
            PhotoUploadSection(
                frontImage: $frontImage,
                backImage: $backImage,
                frontPickerItem: $frontPhotoPickerItem,
                backPickerItem: $backPhotoPickerItem
            )
            SaveButton(
                canSave: canSave,
                action: saveTemplate
            )
        }
        .padding()
    }

    private var templateListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已保存的模板")
                .font(.headline)
                .padding(.horizontal, 16)

            if templateManager.templates.isEmpty {
                EmptyTemplateView()
            } else {
                TemplateListView(
                    templates: templateManager.templates,
                    selectedId: templateManager.selectedTemplateId,
                    onSelect: { template in
                        templateManager.selectTemplate(template)
                    },
                    onDelete: { template in
                        templateToDelete = template
                        showingDeleteAlert = true
                    }
                )
                .padding(.horizontal, 16)
            }
        }
    }

    private var canSave: Bool {
        !templateName.isEmpty && frontImage != nil && backImage != nil
    }

    private func saveTemplate() {
        guard !templateName.isEmpty,
              let front = frontImage,
              let back = backImage else {
            showEmptyNameAlert = true
            return
        }

        if let _ = templateManager.createTemplate(name: templateName, frontImage: front, backImage: back) {
            templateName = ""
            frontImage = nil
            backImage = nil
            frontPhotoPickerItem = nil
            backPhotoPickerItem = nil
        }
    }
}

// MARK: - 模板名称输入
struct TemplateNameField: View {
    @Binding var name: String

    var body: some View {
        HStack {
            Text("模板名称")
                .frame(width: 80, alignment: .leading)
                .foregroundColor(.secondary)
            TextField("例如：乾隆通宝", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - 照片上传区域
struct PhotoUploadSection: View {
    @Binding var frontImage: UIImage?
    @Binding var backImage: UIImage?
    @Binding var frontPickerItem: PhotosPickerItem?
    @Binding var backPickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 16) {
            PhotoUploadRow(
                title: "字面（阴爻）",
                image: $frontImage,
                pickerItem: $frontPickerItem,
                placeholderIcon: "camera",
                placeholderText: "字面"
            )
            PhotoUploadRow(
                title: "图案面（阳爻）",
                image: $backImage,
                pickerItem: $backPickerItem,
                placeholderIcon: "camera",
                placeholderText: "图案"
            )
        }
    }
}

// MARK: - 单个照片上传行
struct PhotoUploadRow: View {
    let title: String
    @Binding var image: UIImage?
    @Binding var pickerItem: PhotosPickerItem?
    let placeholderIcon: String
    let placeholderText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                PhotoPreview(image: image, placeholderIcon: placeholderIcon, placeholderText: placeholderText)
                PhotoPickerButton(pickerItem: $pickerItem, hasImage: image != nil)
                Spacer()
                if image != nil {
                    ClearPhotoButton {
                        image = nil
                        pickerItem = nil
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - 照片预览
struct PhotoPreview: View {
    let image: UIImage?
    let placeholderIcon: String
    let placeholderText: String

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: placeholderIcon)
                                .font(.title3)
                            Text(placeholderText)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    )
            }
        }
    }
}

// MARK: - 照片选择按钮
struct PhotoPickerButton: View {
    @Binding var pickerItem: PhotosPickerItem?
    let hasImage: Bool

    var body: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            HStack {
                Image(systemName: "photo")
                Text(hasImage ? "更换照片" : "选择照片")
            }
            .font(.subheadline)
            .foregroundColor(.blue)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

// MARK: - 清除照片按钮
struct ClearPhotoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(.red)
        }
    }
}

// MARK: - 保存按钮
struct SaveButton: View {
    let canSave: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("保存模板")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(canSave ? Color.blue : Color.gray)
            .cornerRadius(10)
        }
        .disabled(!canSave)
    }
}

// MARK: - 空模板视图
struct EmptyTemplateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("暂无模板")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - 模板列表视图
struct TemplateListView: View {
    let templates: [CoinTemplate]
    let selectedId: UUID?
    let onSelect: (CoinTemplate) -> Void
    let onDelete: (CoinTemplate) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(templates) { template in
                TemplateRow(
                    template: template,
                    isSelected: template.id == selectedId,
                    onSelect: { onSelect(template) },
                    onDelete: { onDelete(template) }
                )
            }
        }
    }
}

// MARK: - 模板行组件
struct TemplateRow: View {
    let template: CoinTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var templateManager: CoinTemplateStorageManager
    @State private var frontImage: Image?
    @State private var backImage: Image?

    var body: some View {
        HStack(spacing: 12) {
            thumbnails
            templateInfo
            Spacer()
            selectedMark
            deleteButton
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
        .cornerRadius(10)
        .onTapGesture(perform: onSelect)
        .onAppear(perform: loadImages)
    }

    private var thumbnails: some View {
        HStack(spacing: 4) {
            Thumbnail(image: frontImage)
            Thumbnail(image: backImage)
        }
    }

    private var templateInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(template.name)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
            Text(formatDate(template.createdDate))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var selectedMark: some View {
        Group {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .foregroundColor(.red)
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - 缩略图组件
struct Thumbnail: View {
    let image: Image?

    var body: some View {
        Group {
            if let img = image {
                img
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
            }
        }
    }
}

#if DEBUG
struct CoinTemplateSetupView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CoinTemplateSetupView()
                .environmentObject(CoinTemplateStorageManager.shared)
        }
    }
}
#endif
