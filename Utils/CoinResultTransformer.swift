import Foundation

struct CoinResultTransformer {
    static func invertSides(_ results: [CoinResult]) -> [CoinResult] {
        results.map { result in
            var next = result
            switch result.side {
            case .front:
                next.side = .back
                next.yinYang = .yang
            case .back:
                next.side = .front
                next.yinYang = .yin
            case .uncertain, .invalid:
                break
            }
            return next
        }
    }
}
