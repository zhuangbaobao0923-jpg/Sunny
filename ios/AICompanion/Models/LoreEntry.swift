import Foundation

/// 世界书条目：角色所在世界的既定设定（地点、势力、人物关系、规则）。
/// 只有用户这句话里出现了 keys，才会被注入上下文——不提到就不占 token。
struct LoreEntry: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var characterID: String
    /// 条目标题，给编辑器认人用（不注入）
    var title: String
    /// 触发词：用户说到这些词时，这条设定才生效
    var keys: [String]
    /// 设定内容，一句话说清
    var content: String
    /// 0 普通 / 1 重要 / 2 核心（同分时优先注入高优先级）
    var priority: Int = 1
    var enabled: Bool = true
    var createdAt: Date = Date()
}
