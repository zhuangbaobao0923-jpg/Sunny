import Foundation

/// 一条记忆：从对话里提炼出来的事实（不是原文）。
/// content 要像人话，例如「用户养了一只猫，叫团子」。
struct MemoryEntry: Codable, Identifiable, Equatable {
    enum Source: String, Codable {
        case rule      // 规则抽取
        case model     // 小模型改写
    }

    var id: String = UUID().uuidString
    var characterID: String
    /// 命中词：用户说到这些词时，这条记忆才被带进上下文
    var keys: [String]
    var content: String
    /// 权重越高越重要（1.0 普通，1.4 家人/恐惧/喜好，3.0 上限）
    var weight: Double = 1.0
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    var source: Source = .rule
}
