import SwiftUI
import UIKit

struct TemplateCenterView: View {
    @EnvironmentObject var dataStorage: DataStorageManager

    @State private var showingCreateTemplate = false
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var profileToRename: CoinProfile?
    @State private var profileToDelete: CoinProfile?
    @State private var profileToPreview: CoinProfile?
    @State private var showingDeleteConfirmation = false

    private var sortedProfiles: [CoinProfile] {
        dataStorage.profiles.sorted { $0.createdDate > $1.createdDate }
    }

    var body: some View {
        List {
            if sortedProfiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无模板")
                        .font(.headline)
                    Text("点击右上角“新增”创建模板")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(sortedProfiles) { profile in
                    Button {
                        profileToPreview = profile
                    } label: {
                        HStack(spacing: 12) {
                            // Thumbnail preview
                            ZStack {
                                if let firstImage = getFirstPreviewImage(profile: profile) {
                                    Image(uiImage: firstImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipped()
                                        .cornerRadius(8)
                                } else {
                                    Image(systemName: "photo")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, height: 60)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(8)
                                }
                            }

                            // Info section
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(profile.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    if profile.id == dataStorage.activeProfileId {
                                        Text("当前")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15))
                                            .cornerRadius(6)
                                    }
                                }

                                Text("创建于 \(formatDate(profile.createdDate))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack(spacing: 4) {
                                    Label("\(getPreviewImageCount(profile: profile))张", systemImage: "photo.fill")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    if profile.id == dataStorage.activeProfileId {
                                        Spacer()
                                        Text("识别中")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    } else {
                                        Spacer()
                                        Text("点击查看详情")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("重命名") {
                            profileToRename = profile
                            renameText = profile.name
                            showingRenameAlert = true
                        }
                        .tint(.blue)

                        Button("删除", role: .destructive) {
                            profileToDelete = profile
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
        }
        .navigationTitle("模板中心")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("新增") {
                    showingCreateTemplate = true
                }
            }
        }
        .navigationDestination(isPresented: $showingCreateTemplate) {
            SetupProfileView()
        }
        .sheet(item: $profileToPreview) { profile in
            NavigationStack {
                TemplatePreviewGalleryView(
                    profile: profile,
                    isCurrentProfile: profile.id == dataStorage.activeProfileId,
                    onSetCurrent: {
                        dataStorage.setActiveProfile(profile.id)
                    }
                )
            }
        }
        .alert("重命名模板", isPresented: $showingRenameAlert) {
            TextField("模板名称", text: $renameText)
            Button("取消", role: .cancel) {
                profileToRename = nil
            }
            Button("保存") {
                if let id = profileToRename?.id {
                    dataStorage.renameProfile(id, name: renameText)
                }
                profileToRename = nil
            }
        } message: {
            Text("请输入新的模板名称")
        }
        .alert("确认删除", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {
                profileToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let profile = profileToDelete {
                    dataStorage.deleteProfile(profile)
                }
                profileToDelete = nil
            }
        } message: {
            if let profile = profileToDelete {
                Text("确定要删除模板「\(profile.name)」吗？\n删除后无法恢复。")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    // Helper functions for thumbnail display
    private func getFirstPreviewImage(profile: CoinProfile) -> UIImage? {
        let allImages = decodeImages(from: profile.frontPreviewImages) + decodeImages(from: profile.backPreviewImages)
        return allImages.first
    }

    private func getPreviewImageCount(profile: CoinProfile) -> Int {
        return profile.frontPreviewImages.count + profile.backPreviewImages.count
    }

    private func decodeImages(from rawImages: [Data]) -> [UIImage] {
        rawImages.compactMap { UIImage(data: $0) }
    }
}

private struct TemplatePreviewGalleryView: View {
    @Environment(\.dismiss) private var dismiss

    let profile: CoinProfile
    let isCurrentProfile: Bool
    let onSetCurrent: () -> Void

    @State private var fullScreenPreview: TemplateFullScreenPreview?

    private var frontImages: [UIImage] {
        decodeImages(from: profile.frontPreviewImages)
    }

    private var backImages: [UIImage] {
        decodeImages(from: profile.backPreviewImages)
    }

    private var hasImages: Bool {
        !frontImages.isEmpty || !backImages.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.name)
                        .font(.title3.bold())
                    Text("创建于 \(formatDate(profile.createdDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !isCurrentProfile {
                    Button("设为当前模板") {
                        onSetCurrent()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Label("当前识别模板", systemImage: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }

                if hasImages {
                    previewSection(title: "阴面模板", images: frontImages)
                    previewSection(title: "阳面模板", images: backImages)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("暂无可预览模板图")
                            .font(.headline)
                        Text("该模板可能由旧版本创建。可重新录入模板后查看图片。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
            .padding(16)
        }
        .navigationTitle("模板图片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
                    dismiss()
                }
            }
        }
        .fullScreenCover(item: $fullScreenPreview) { preview in
            TemplateImagePagerView(
                images: preview.images,
                initialIndex: preview.initialIndex,
                title: preview.title
            )
        }
    }

    @ViewBuilder
    private func previewSection(title: String, images: [UIImage]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(images.count)张")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if images.isEmpty {
                Text("暂无图片")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                    ForEach(images.indices, id: \.self) { index in
                        Button {
                            fullScreenPreview = TemplateFullScreenPreview(
                                title: title,
                                images: images,
                                initialIndex: index
                            )
                        } label: {
                            Image(uiImage: images[index])
                                .resizable()
                                .scaledToFill()
                                .frame(height: 90)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .cornerRadius(10)
                                .overlay(alignment: .bottomTrailing) {
                                    Text("\(index + 1)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Color.black.opacity(0.65))
                                        .cornerRadius(6)
                                        .padding(4)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func decodeImages(from rawImages: [Data]) -> [UIImage] {
        rawImages.compactMap { UIImage(data: $0) }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

private struct TemplateFullScreenPreview: Identifiable {
    let id = UUID()
    let title: String
    let images: [UIImage]
    let initialIndex: Int
}

private struct TemplateImagePagerView: View {
    @Environment(\.dismiss) private var dismiss

    let images: [UIImage]
    let title: String

    @State private var currentIndex: Int

    init(images: [UIImage], initialIndex: Int, title: String) {
        self.images = images
        self.title = title
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if images.isEmpty {
                    Text("暂无图片")
                        .foregroundColor(.white.opacity(0.8))
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(images.indices, id: \.self) { index in
                            Image(uiImage: images[index])
                                .resizable()
                                .scaledToFit()
                                .tag(index)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 24)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                }
            }
            .navigationTitle("\(title) \(images.isEmpty ? 0 : currentIndex + 1)/\(images.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#if DEBUG
struct TemplateCenterView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TemplateCenterView()
                .environmentObject(DataStorageManager.shared)
        }
    }
}
#endif
