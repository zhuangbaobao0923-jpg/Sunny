import Foundation

// MARK: - 聊天记录本地持久化

/// 每个角色一份快照：聊天记录 + 亲密度回合数 + 点赞状态。
/// 用户退出聊天 / 杀掉 App 再进来，记录和等级都保留（本地 JSON，无云端依赖）。
struct ChatSnapshot: Codable {
    struct SavedMessage: Codable {
        var role: String   // "user" / "assistant"
        var text: String
        var date: Date
    }

    var messages: [SavedMessage] = []
    var rounds: Int = 0
    var likeCount: Int = 0
    var liked: Bool = false
    var lastUpdated: Date = Date()
}

enum ChatHistoryStorage {
    private static let prefix = "chat.history."

    static func load(characterID: String) -> ChatSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: prefix + characterID) else { return nil }
        return try? JSONDecoder().decode(ChatSnapshot.self, from: data)
    }

    static func save(_ snapshot: ChatSnapshot, characterID: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: prefix + characterID)
    }

    /// 只保留可展示的消息：失败气泡、流式中的空段、空文本不落盘
    static func snapshot(
        messages: [ChatMessage],
        rounds: Int,
        likeCount: Int,
        liked: Bool
    ) -> ChatSnapshot {
        let saved = messages
            .filter { !$0.failed && !$0.streaming && !$0.text.isEmpty }
            .map { ChatSnapshot.SavedMessage(role: $0.role == .user ? "user" : "assistant", text: $0.text, date: $0.date) }
        return ChatSnapshot(messages: saved, rounds: rounds, likeCount: likeCount, liked: liked)
    }
}
