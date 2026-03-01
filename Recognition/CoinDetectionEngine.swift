import CoreGraphics
import UIKit

enum CoinCropHintKind: String, Codable {
    case adjust
    case add
}

struct CoinCropHint: Codable {
    var position: Int
    var normalizedRect: CGRect
    var kind: CoinCropHintKind

    init(position: Int, normalizedRect: CGRect, kind: CoinCropHintKind) {
        self.position = position
        self.normalizedRect = normalizedRect
        self.kind = kind
    }
}

protocol CoinDetectionEngine {
    func detectCoins(in image: UIImage) async -> [CoinDetector.DetectedCoin]
    func redetectCoins(in image: UIImage, hints: [CoinCropHint]) async -> [CoinDetector.DetectedCoin]
}
