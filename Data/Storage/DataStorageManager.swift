import Foundation
import Combine

@MainActor
class DataStorageManager: ObservableObject {
    static let shared = DataStorageManager()
    
    @Published var profiles: [CoinProfile] = []
    @Published var activeProfileId: UUID?
    @Published var sessions: [DivinationSession] = []
    
    private let profilesKey = "coin_profiles"
    private let activeProfileIdKey = "active_profile_id"
    private let sessionsKey = "divination_sessions"
    
    private init() {
        resetForUITestingIfNeeded()
        loadData()
    }
    
    // MARK: - Data Loading
    private func loadData() {
        loadProfiles()
        loadActiveProfileId()
        ensureActiveProfileSelection()
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

    private func loadActiveProfileId() {
        if let rawValue = UserDefaults.standard.string(forKey: activeProfileIdKey),
           let id = UUID(uuidString: rawValue) {
            activeProfileId = id
        }
    }
    
    // MARK: - Data Saving
    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: profilesKey)
        }
    }

    private func saveActiveProfileId() {
        UserDefaults.standard.set(activeProfileId?.uuidString, forKey: activeProfileIdKey)
    }
    
    private func saveSessions() {
        if let encoded = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: sessionsKey)
        }
    }
    
    // MARK: - Profile Management
    var activeProfile: CoinProfile? {
        guard let activeProfileId else { return nil }
        return profiles.first(where: { $0.id == activeProfileId })
    }

    func createProfile(name: String, frontTemplates: Data, backTemplates: Data) -> CoinProfile {
        let profile = CoinProfile(name: name, frontTemplates: frontTemplates, backTemplates: backTemplates)
        profiles.append(profile)
        saveProfiles()
        setActiveProfile(profile.id)
        return profile
    }
    
    func deleteProfile(_ profile: CoinProfile) {
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
        ensureActiveProfileSelection()
    }
    
    func updateProfile(_ profile: CoinProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
            ensureActiveProfileSelection()
        }
    }

    func setActiveProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
        saveActiveProfileId()
    }

    func renameProfile(_ id: UUID, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmedName
        saveProfiles()
    }
    
    // MARK: - Session Management
    func createSession(source: SessionSource, profileId: UUID? = nil, results: [CoinResult]?) -> DivinationSession {
        let resolvedProfileId = profileId ?? activeProfileId
        let session = DivinationSession(source: source, profileId: resolvedProfileId, results: results)
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
        UserDefaults.standard.removeObject(forKey: profilesKey)
        UserDefaults.standard.removeObject(forKey: activeProfileIdKey)
        UserDefaults.standard.removeObject(forKey: sessionsKey)
        profiles = []
        activeProfileId = nil
        sessions = []

        if args.contains("-ui-testing-seed-profile") {
            let seededProfile = CoinProfile(
                name: "UI Test Template",
                frontTemplates: Data(),
                backTemplates: Data()
            )
            profiles = [seededProfile]
            activeProfileId = seededProfile.id
            saveProfiles()
            saveActiveProfileId()
        }
    }

    private func ensureActiveProfileSelection() {
        guard !profiles.isEmpty else {
            activeProfileId = nil
            saveActiveProfileId()
            return
        }

        if let activeProfileId, profiles.contains(where: { $0.id == activeProfileId }) {
            saveActiveProfileId()
            return
        }

        if let latestProfile = profiles.max(by: { $0.createdDate < $1.createdDate }) {
            activeProfileId = latestProfile.id
            saveActiveProfileId()
        }
    }
}
