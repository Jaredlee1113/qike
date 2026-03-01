import Foundation
import CoreGraphics

struct DetectionDraft: Identifiable, Equatable {
    let id: UUID
    var centerNormalized: CGPoint
    var sizeNormalized: CGSize
    var positionHint: Int?

    init(
        id: UUID = UUID(),
        centerNormalized: CGPoint,
        sizeNormalized: CGSize,
        positionHint: Int? = nil
    ) {
        self.id = id
        self.centerNormalized = centerNormalized
        self.sizeNormalized = sizeNormalized
        self.positionHint = positionHint
    }
}

enum DetectionFailureReason {
    case notEnoughCoins
    case qualityRejected
    case reliabilityRejected
    case legacyTemplate

    var hintText: String {
        switch self {
        case .notEnoughCoins:
            return "自动检测不足6枚，请拖动框对准每枚铜钱后重新识别。"
        case .qualityRejected:
            return "画面质量不足，请微调框位并尽量避开反光后重试。"
        case .reliabilityRejected:
            return "阴阳判定稳定性不足，请微调框位后重新识别。"
        case .legacyTemplate:
            return "模板版本过旧，请先重录模板。"
        }
    }
}
