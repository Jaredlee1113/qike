import Foundation

struct DivinationSession: Identifiable, Codable {
    var id: UUID
    var date: Date
    var source: String
    var profileId: UUID
    var results: [CoinResult]?
    var imagePaths: [String]?
    var roiPaths: [String]?
    
    init(source: String, profileId: UUID, results: [CoinResult]? = nil, imagePaths: [String]? = nil, roiPaths: [String]? = nil) {
        self.id = UUID()
        self.date = Date()
        self.source = source
        self.profileId = profileId
        self.results = results
        self.imagePaths = imagePaths
        self.roiPaths = roiPaths
    }
}