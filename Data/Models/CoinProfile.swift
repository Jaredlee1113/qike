import Foundation

struct CoinProfile: Identifiable, Codable {
    var id: UUID
    var name: String
    var frontTemplates: Data
    var backTemplates: Data
    var createdDate: Date
    
    init(name: String, frontTemplates: Data = Data(), backTemplates: Data = Data()) {
        self.id = UUID()
        self.name = name
        self.frontTemplates = frontTemplates
        self.backTemplates = backTemplates
        self.createdDate = Date()
    }
}