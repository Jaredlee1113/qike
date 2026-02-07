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

        return Self.resolveSmoothedScores(frontScore: frontScore, backScore: backScore)
    }

    static func resolveSmoothedScores(
        frontScore: Double,
        backScore: Double
    ) -> (CoinSide, Double) {
        let totalScore = frontScore + backScore
        guard totalScore > 0 else { return (.invalid, 0.0) }

        let confidence = max(frontScore, backScore) / totalScore
        let delta = abs(frontScore - backScore) / totalScore
        if delta < 0.08 && confidence < 0.58 {
            return (.uncertain, confidence)
        }

        let side: CoinSide = frontScore > backScore ? .front : .back
        return (side, confidence)
    }
}

enum ResultReliabilityEvaluator {
    struct Calibration {
        let minPerCoinConfidence: Double
        let minAverageConfidence: Double
        let maxLowConfidenceCount: Int

        static let `default` = Calibration(
            minPerCoinConfidence: 0.57,
            minAverageConfidence: 0.66,
            maxLowConfidenceCount: 1
        )
    }

    static func isReliable(
        _ results: [CoinResult],
        calibration: Calibration = .default
    ) -> Bool {
        guard results.count == 6 else { return false }
        guard Set(results.map(\.position)).count == 6 else { return false }
        guard results.allSatisfy({ $0.side == .front || $0.side == .back }) else {
            return false
        }

        let confidences = results.map { min(max($0.confidence, 0), 1) }
        let lowConfidenceCount = confidences.filter { $0 < calibration.minPerCoinConfidence }.count
        guard lowConfidenceCount <= calibration.maxLowConfidenceCount else { return false }

        let averageConfidence = confidences.reduce(0, +) / Double(confidences.count)
        return averageConfidence >= calibration.minAverageConfidence
    }
}
