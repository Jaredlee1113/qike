import Foundation
import Combine

@MainActor
class DataStorageManager: ObservableObject {
    static let shared = DataStorageManager()

    @Published var sessions: [DivinationSession] = []

    private let sessionsKey = "divination_sessions"

    private init() {
        resetForUITestingIfNeeded()
        loadSessions()
    }

    // MARK: - Data Loading
    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([DivinationSession].self, from: data) {
            sessions = decoded
        }
    }

    // MARK: - Data Saving
    private func saveSessions() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: sessionsKey)
        }
    }

    // MARK: - Session Management
    func createSession(source: SessionSource, profileId: UUID? = nil, results: [CoinResult]?) -> DivinationSession {
        let session = DivinationSession(source: source, profileId: nil, results: results)
        sessions.append(session)
        saveSessions()
        return session
    }

    func deleteSession(_ session: DivinationSession) {
        sessions.removeAll { $0.id == session.id }
        saveSessions()
    }

    func getSortedSessions() -> [DivinationSession] {
        return sessions.sorted { $0.date > $1.date }
    }

    private func resetForUITestingIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-ui-testing") else { return }
        UserDefaults.standard.removeObject(forKey: sessionsKey)
        sessions = []
    }
}
