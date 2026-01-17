import Foundation

enum YinYang: String, Codable {
    case yang = "阳"
    case yin = "阴"
}

enum CoinSide: String, Codable {
    case front = "字面"
    case back = "图案面"
    case invalid = "无效"
}

struct CoinResult: Identifiable, Codable {
    let id = UUID()
    var position: Int
    var yinYang: YinYang
    var side: CoinSide
    var confidence: Double
    
    init(position: Int, yinYang: YinYang = .yang, side: CoinSide = .invalid, confidence: Double = 0.0) {
        self.position = position
        self.yinYang = yinYang
        self.side = side
        self.confidence = confidence
    }
}