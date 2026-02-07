import SwiftUI

struct TemplateCenterView: View {
    @EnvironmentObject var dataStorage: DataStorageManager

    @State private var showingCreateTemplate = false
    @State private var showingRenameAlert = false
    @State private var renameText = ""
    @State private var profileToRename: CoinProfile?
    @State private var profileToDelete: CoinProfile?
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

                            Spacer()

                            if profile.id != dataStorage.activeProfileId {
                                Button("设为当前") {
                                    dataStorage.setActiveProfile(profile.id)
                                }
                                .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dataStorage.setActiveProfile(profile.id)
                    }
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
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
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
