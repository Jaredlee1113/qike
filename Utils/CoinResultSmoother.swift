import Foundation

struct CoinResultSmoother {
    let windowSize: Int
    let minimumSamples: Int
    private var history: [Int: [(CoinSide, Double)]] = [:]

    init(windowSize: Int = 8, minimumSamples: Int = 4) {
        self.windowSize = max(windowSize, 1)
        self.minimumSamples = max(minimumSamples, 1)
    }

    mutating func add(results: [CoinResult]) -> [CoinResult] {
        guard !results.isEmpty else { return results }

        var updated: [CoinResult] = []
        updated.reserveCapacity(results.count)

        for result in results {
            let position = result.position

            if result.side == .front || result.side == .back {
                var list = history[position, default: []]
                list.append((result.side, result.confidence))
                if list.count > windowSize {
                    list.removeFirst(list.count - windowSize)
                }
                history[position] = list
            }

            let (smoothedSide, smoothedConfidence) = smoothSide(
                for: position,
                fallback: result.side,
                fallbackConfidence: result.confidence
            )

            var next = result
            next.side = smoothedSide
            next.confidence = smoothedConfidence

            if smoothedSide == .front {
                next.yinYang = .yin
            } else if smoothedSide == .back {
                next.yinYang = .yang
            }

            updated.append(next)
        }

        return updated
    }

    mutating func reset() {
        history.removeAll()
    }

    private func smoothSide(
        for position: Int,
        fallback: CoinSide,
        fallbackConfidence: Double
    ) -> (CoinSide, Double) {
        guard let list = history[position],
              list.count >= minimumSamples else {
            return (fallback, fallbackConfidence)
        }

        var frontScore = 0.0
        var backScore = 0.0
        for entry in list {
            if entry.0 == .front {
                frontScore += entry.1
            } else if entry.0 == .back {
                backScore += entry.1
            }
        }

        let totalScore = frontScore + backScore
        guard totalScore > 0 else { return (fallback, fallbackConfidence) }

        let delta = abs(frontScore - backScore) / totalScore
        if delta < 0.15 {
            let confidence = max(frontScore, backScore) / totalScore
            return (.uncertain, confidence)
        }

        let side: CoinSide = frontScore > backScore ? .front : .back
        let confidence = max(frontScore, backScore) / totalScore
        return (side, confidence)
    }
}
