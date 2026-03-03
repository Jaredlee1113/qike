import Foundation

/// 铜钱模板数据模型
struct CoinTemplate: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdDate: Date
    var frontImageName: String  // 字面（阴）
    var backImageName: String   // 图案面（阳）
}

/// 铜钱面
enum CoinFace: String, CaseIterable {
    case front = "字面"  // 阴
    case back = "图案面"  // 阳
}
