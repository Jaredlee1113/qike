import Foundation
import Combine

class DataStorageManager: ObservableObject {
    static let shared = DataStorageManager()
    
    @Published var profiles: [CoinProfile] = []
    @Published var sessions: [DivinationSession] = []
    
    private let profilesKey = "coin_profiles"
    private let sessionsKey = "divination_sessions"
    
    private init() {
        resetForUITestingIfNeeded()
        loadData()
    }
    
    // MARK: - Data Loading
    private func loadData() {
        loadProfiles()
        loadSessions()
    }
    
    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([CoinProfile].self, from: data) {
            profiles = decoded
        }
    }
    
    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([DivinationSession].self, from: data) {
            sessions = decoded
        }
    }
    
    // MARK: - Data Saving
    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }
    }
    
    private func saveSessions() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: sessionsKey)
        }
    }
    
    // MARK: - Profile Management
    func createProfile(name: String, frontTemplates: Data, backTemplates: Data) -> CoinProfile {
        let profile = CoinProfile(name: name, frontTemplates: frontTemplates, backTemplates: backTemplates)
        profiles.append(profile)
        saveProfiles()
        return profile
    }
    
    func deleteProfile(_ profile: CoinProfile) {
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
    }
    
    func updateProfile(_ profile: CoinProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
        }
    }
    
    // MARK: - Session Management
    func createSession(source: String, profileId: UUID, results: [CoinResult]?) -> DivinationSession {
        let session = DivinationSession(source: source, profileId: profileId, results: results)
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
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
        UserDefaults.standard.removeObject(forKey: profilesKey)
        UserDefaults.standard.removeObject(forKey: sessionsKey)
        profiles = []
        sessions = []
    }
}
