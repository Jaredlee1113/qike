import Foundation

enum SessionSource: String, Codable {
    case camera
    case photo
    case manual

    var displayName: String {
        switch self {
        case .camera:
            return "相机拍摄"
        case .photo:
            return "相册选择"
        case .manual:
            return "手动输入"
        }
    }
}

struct DivinationSession: Identifiable, Codable {
    var id: UUID
    var date: Date
    var source: String
    var profileId: UUID?
    var results: [CoinResult]?
    var imagePaths: [String]?
    var roiPaths: [String]?

    var sourceType: SessionSource {
        SessionSource(rawValue: source) ?? .camera
    }

    init(
        source: SessionSource,
        profileId: UUID?,
        results: [CoinResult]? = nil,
        imagePaths: [String]? = nil,
        roiPaths: [String]? = nil
    ) {
        self.id = UUID()
        self.date = Date()
        self.source = source.rawValue
        self.profileId = profileId
        self.results = results
        self.imagePaths = imagePaths
        self.roiPaths = roiPaths
    }
}
