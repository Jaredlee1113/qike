import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var dataStorage: DataStorageManager

    var sortedSessions: [DivinationSession] {
        dataStorage.getSortedSessions()
    }

    var body: some View {
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
            } else {
                ForEach(sortedSessions) { session in
                    NavigationLink(destination: SessionDetailView(session: session)) {
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

                            if let results = session.results, let hexagram = HexagramProvider.findHexagram(by: results.map { $0.yinYang }) {
                                Text(hexagram.name)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { offsets in
                    deleteSessions(offsets: offsets)
                }
            }
        }
        .navigationTitle("历史记录")
    }

    private func deleteSessions(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let sessionToDelete = sortedSessions[index]
                dataStorage.deleteSession(sessionToDelete)
            }
        }
    }

    private func profileName(for session: DivinationSession) -> String {
        guard let profileId = session.profileId else { return "未关联模板" }
        return dataStorage.profiles.first(where: { $0.id == profileId })?.name ?? "模板已删除"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
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
