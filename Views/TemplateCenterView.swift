import SwiftUI
import UIKit

struct TemplateCenterView: View {
    @EnvironmentObject var dataStorage: DataStorageManager

    @State private var showingCreateTemplate = false
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var profileToRename: CoinProfile?
    @State private var profileToDelete: CoinProfile?
    @State private var profileToReset: CoinProfile?
    @State private var profileToPreview: CoinProfile?
    @State private var showingDeleteConfirmation = false
    @State private var showingResetConfirmation = false
    @State private var isResettingProfileId: UUID?
    @State private var resetAlertMessage: String?
    @State private var showingResetAlert = false

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
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(profile.name)
                                .font(.headline)

                            if profile.id == dataStorage.activeProfileId {
                                Text("当前")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }

                            Spacer()
                        }

                        HStack {
                            Text("创建于 \(formatDate(profile.createdDate))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if isResettingProfileId == profile.id {
                                Text("重置中…")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }

                            Spacer()

                            if profile.id != dataStorage.activeProfileId {
                                Button("设为当前") {
                                    dataStorage.setActiveProfile(profile.id)
                                }
                                .font(.caption)
                            }
                        }

                        HStack(spacing: 8) {
                            Button {
                                profileToPreview = profile
                            } label: {
                                Label("查看模板", systemImage: "photo.on.rectangle.angled")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)

                            if profile.id == dataStorage.activeProfileId {
                                Text("当前识别使用该模板")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dataStorage.setActiveProfile(profile.id)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("清空增量") {
                            profileToReset = profile
                            showingResetConfirmation = true
                        }
                        .tint(.orange)

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
                    .disabled(isResettingProfileId != nil)
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
        .confirmationDialog(
            "删除后无法恢复，是否继续？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除模板", role: .destructive) {
                if let profile = profileToDelete {
                    dataStorage.deleteProfile(profile)
                }
                profileToDelete = nil
            }
            Button("取消", role: .cancel) {
                profileToDelete = nil
            }
        }
        .confirmationDialog(
            "将清空该模板的增量学习样本，仅保留初始模板。是否继续？",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空增量样本", role: .destructive) {
                guard let profile = profileToReset else { return }
                isResettingProfileId = profile.id
                Task {
                    let success = await dataStorage.resetLearnedSamples(for: profile.id)
                    await MainActor.run {
                        isResettingProfileId = nil
                        if success {
                            resetAlertMessage = "已清空增量样本，模板已恢复为初始版本。"
                        } else {
                            resetAlertMessage = "清空失败：缺少可重建的模板数据，请重新录入模板。"
                        }
                        showingResetAlert = true
                    }
                }
                profileToReset = nil
            }
            Button("取消", role: .cancel) {
                profileToReset = nil
            }
        }
        .alert("重置模板", isPresented: $showingResetAlert) {
            Button("确定", role: .cancel) {
                resetAlertMessage = nil
            }
        } message: {
            Text(resetAlertMessage ?? "")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
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
