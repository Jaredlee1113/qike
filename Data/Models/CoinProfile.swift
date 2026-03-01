import Foundation

struct CoinProfile: Identifiable, Codable {
    var id: UUID
    var name: String
    var frontTemplates: Data
    var backTemplates: Data
    var baseFrontTemplates: Data
    var baseBackTemplates: Data
    var frontPreviewImages: [Data]
    var backPreviewImages: [Data]
    var createdDate: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case frontTemplates
        case backTemplates
        case baseFrontTemplates
        case baseBackTemplates
        case frontPreviewImages
        case backPreviewImages
        case createdDate
    }

    init(
        name: String,
        frontTemplates: Data = Data(),
        backTemplates: Data = Data(),
        baseFrontTemplates: Data? = nil,
        baseBackTemplates: Data? = nil,
        frontPreviewImages: [Data] = [],
        backPreviewImages: [Data] = []
    ) {
        self.id = UUID()
        self.name = name
        self.frontTemplates = frontTemplates
        self.backTemplates = backTemplates
        self.baseFrontTemplates = baseFrontTemplates ?? frontTemplates
        self.baseBackTemplates = baseBackTemplates ?? backTemplates
        self.frontPreviewImages = frontPreviewImages
        self.backPreviewImages = backPreviewImages
        self.createdDate = Date()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        frontTemplates = try container.decode(Data.self, forKey: .frontTemplates)
        backTemplates = try container.decode(Data.self, forKey: .backTemplates)
        baseFrontTemplates = try container.decodeIfPresent(Data.self, forKey: .baseFrontTemplates) ?? frontTemplates
        baseBackTemplates = try container.decodeIfPresent(Data.self, forKey: .baseBackTemplates) ?? backTemplates
        frontPreviewImages = try container.decodeIfPresent([Data].self, forKey: .frontPreviewImages) ?? []
        backPreviewImages = try container.decodeIfPresent([Data].self, forKey: .backPreviewImages) ?? []
        createdDate = try container.decodeIfPresent(Date.self, forKey: .createdDate) ?? Date()
    }
}
