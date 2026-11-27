import Foundation

/// 记录「这一轮到底往提示词里塞了什么」，用于自测取证。
/// 长按聊天页标题可以查看，避免只能靠回复内容猜。
enum PromptTrace {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _time = ""
    nonisolated(unsafe) private static var _lore: [String] = []
    nonisolated(unsafe) private static var _memory: [String] = []

    static func record(time: String, lore: [LoreEntry], memory: [MemoryEntry]) {
        lock.lock(); defer { lock.unlock() }
        _time = time
        _lore = lore.map { "\($0.title)：\($0.content)" }
        _memory = memory.map { $0.content }
    }

    static var snapshot: (time: String, lore: [String], memory: [String]) {
        lock.lock(); defer { lock.unlock() }
        return (_time, _lore, _memory)
    }
}
