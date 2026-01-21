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
                                Text(session.source == "camera" ? "相机拍摄" : "相册选择")
                                    .font(.caption)
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

struct SessionDetailView: View {
    let session: DivinationSession
    
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
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("识别结果")
                        .font(.headline)
                    
                    if let results = session.results {
                        ForEach(results.sorted { $0.position < $1.position }, id: \.position) { result in
                            HStack {
                                Text("第\(result.position)爻")
                                    .frame(width: 60, alignment: .leading)
                                
                                Text(result.yinYang.rawValue)
                                    .fontWeight(.bold)
                                    .foregroundColor(result.yinYang == .yang ? .blue : .red)
                                
                                Spacer()
                                
                                Text("\(Int(result.confidence * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                if let results = session.results, let hexagram = HexagramProvider.findHexagram(by: results.map { $0.yinYang }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("卦象信息")
                            .font(.headline)
                        
                        HStack {
                            Text(hexagram.hexagramSymbol)
                                .font(.system(size: 48))
                                .frame(width: 60)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(hexagram.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("占卜图解: \(hexagram.divinationDiagramName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("爻词")
                            .font(.headline)
                        
                        ForEach(0..<hexagram.yaoci.count, id: \.self) { index in
                            Text(hexagram.yaoci[index])
                                .font(.body)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("卦象解释")
                            .font(.headline)
                        
                        Text(hexagram.explanation)
                            .font(.body)
                            .lineLimit(10...50)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
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
}

#Preview {
    let dataStorage = DataStorageManager.shared

    return NavigationStack {
        HistoryView()
    }
    .environmentObject(dataStorage)
}
