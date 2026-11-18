import Foundation

struct ChatMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
    let date: Date
    /// 请求失败留下的可重试气泡
    var failed: Bool = false
    /// 正在流式增长的段落
    var streaming: Bool = false

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text, date: Date())
    }

    static func assistant(_ text: String, streaming: Bool = false) -> ChatMessage {
        ChatMessage(role: .assistant, text: text, date: Date(), streaming: streaming)
    }

    static func failure(_ reason: String) -> ChatMessage {
        ChatMessage(role: .assistant, text: reason, date: Date(), failed: true)
    }
}
