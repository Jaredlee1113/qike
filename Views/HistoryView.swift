import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var dataStorage: DataStorageManager
    @State private var searchText = ""
    @State private var selectedSourceFilter: SourceFilter = .all

    var sortedSessions: [DivinationSession] {
        dataStorage.getSortedSessions()
    }

    private var filteredSessions: [DivinationSession] {
        sortedSessions.filter { session in
            sourceMatches(session) && searchMatches(session)
        }
    }

    private var groupedSessions: [(day: Date, sessions: [DivinationSession])] {
        let grouped = Dictionary(grouping: filteredSessions) { session in
            Calendar.current.startOfDay(for: session.date)
        }

        return grouped
            .map { (day: $0.key, sessions: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("来源筛选", selection: $selectedSourceFilter) {
                ForEach(SourceFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)

            List {
                if sortedSessions.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无历史记录")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if filteredSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("没有匹配记录")
                            .font(.headline)
                        Text("试试更换筛选条件或关键词")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    ForEach(groupedSessions, id: \.day) { group in
                        Section(header: sectionHeader(for: group.day)) {
                            ForEach(group.sessions) { session in
                                NavigationLink(destination: SessionDetailView(session: session)) {
                                    sessionRow(session)
                                }
                            }
                            .onDelete { offsets in
                                deleteSessions(in: group, offsets: offsets)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("历史记录")
        .searchable(text: $searchText, prompt: "搜索卦名、模板、来源")
    }

    private func deleteSessions(in group: (day: Date, sessions: [DivinationSession]), offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let sessionToDelete = group.sessions[index]
                dataStorage.deleteSession(sessionToDelete)
            }
        }
    }

    private func sessionRow(_ session: DivinationSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(session.date))
                    .font(.headline)
                Text(session.sourceType.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("模板：\(profileName(for: session))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let name = hexagramName(for: session) {
                Text(name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private func sectionHeader(for day: Date) -> some View {
        Text(formatDay(day))
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)
    }

    private func sourceMatches(_ session: DivinationSession) -> Bool {
        switch selectedSourceFilter {
        case .all:
            return true
        case .camera:
            return session.sourceType == .camera
        case .photo:
            return session.sourceType == .photo
        case .manual:
            return session.sourceType == .manual
        }
    }

    private func searchMatches(_ session: DivinationSession) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let fields: [String] = [
            session.sourceType.displayName,
            profileName(for: session),
            hexagramName(for: session) ?? ""
        ]

        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func hexagramName(for session: DivinationSession) -> String? {
        guard let results = session.results else { return nil }
        return HexagramProvider.findHexagram(by: results.map { $0.yinYang })?.name
    }

    private func profileName(for session: DivinationSession) -> String {
        guard let profileId = session.profileId else { return "未关联模板" }
        return dataStorage.profiles.first(where: { $0.id == profileId })?.name ?? "模板已删除"
    }

    private func formatDay(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "今天"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "昨天"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

private enum SourceFilter: String, CaseIterable, Identifiable {
    case all
    case camera
    case photo
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .camera:
            return "拍摄"
        case .photo:
            return "相册"
        case .manual:
            return "手动"
        }
    }
}

struct SessionDetailView: View {
    @EnvironmentObject var dataStorage: DataStorageManager
    let session: DivinationSession

    private var yaos: [YinYang]? {
        session.results?
            .sorted { $0.position < $1.position }
            .map(\.yinYang)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("起课时间")
                        .font(.headline)
                    Text(formatDate(session.date))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)

                VStack(alignment: .leading, spacing: 8) {
                    Text("来源")
                        .font(.headline)
                    Text(session.sourceType.displayName)
                        .font(.body)
                        .foregroundColor(.secondary)

                    Text("模板")
                        .font(.headline)
                    Text(profileName(for: session))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)

                if let yaos,
                   let hexagram = HexagramProvider.findHexagram(by: yaos) {
                    HexagramDisplay(hexagram: hexagram)
                } else {
                    Text("未找到对应的卦象")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }
            }
            .padding()
        }
        .navigationTitle("起课详情")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func profileName(for session: DivinationSession) -> String {
        guard let profileId = session.profileId else { return "未关联模板" }
        return dataStorage.profiles.first(where: { $0.id == profileId })?.name ?? "模板已删除"
    }
}

#if DEBUG
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        let dataStorage = DataStorageManager.shared
        return NavigationStack {
            HistoryView()
        }
        .environmentObject(dataStorage)
    }
}
#endif
