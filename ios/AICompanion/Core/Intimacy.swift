import Foundation

/// 亲密度：一问一答 = 1 回合；每 20 回合升 1 级；Lv.5 封顶并解锁语音通话。
/// 纯值类型，不依赖 UI 框架，便于单测。
struct IntimacyProgress: Equatable {
    static let roundsPerLevel = 20
    static let maxLevel = 5

    private(set) var rounds: Int = 0

    init(rounds: Int = 0) {
        self.rounds = max(0, rounds)
    }

    var level: Int {
        min(Self.maxLevel, rounds / Self.roundsPerLevel + 1)
    }

    var isMaxLevel: Bool { level >= Self.maxLevel }

    /// 当前等级内已积累的回合数（满级后不再增长）
    var roundsIntoLevel: Int {
        isMaxLevel ? Self.roundsPerLevel : rounds % Self.roundsPerLevel
    }

    var roundsNeeded: Int { Self.roundsPerLevel }

    var progress: Double {
        guard !isMaxLevel else { return 1 }
        return Double(roundsIntoLevel) / Double(Self.roundsPerLevel)
    }

    var counterText: String { "(\(roundsIntoLevel)/\(roundsNeeded))" }

    /// 语音通话在 Lv.5 解锁
    var voiceUnlocked: Bool { isMaxLevel }

    /// 记一回合，返回是否发生升级
    @discardableResult
    mutating func recordTurn() -> Bool {
        guard !isMaxLevel else { return false }
        let before = level
        rounds += 1
        return level > before
    }
}
