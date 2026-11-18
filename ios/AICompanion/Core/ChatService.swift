import Foundation

enum ChatError: LocalizedError, Equatable {
    case timeout
    case offline

    var errorDescription: String? {
        switch self {
        case .timeout: return "对方似乎走神了"
        case .offline: return "网络开小差了"
        }
    }
}

/// 对话流式输出。真模型走 RemoteChatService（OpenAI 兼容 SSE），本地演示走 MockChatService，UI 层无需改动。
protocol ChatService {
    func streamReply(
        for character: Character,
        history: [ChatMessage],
        userText: String,
        level: Int,
        memory: [MemoryTurn]
    ) -> AsyncThrowingStream<String, Error>
}

extension ChatService {
    /// 兼容旧调用：不带记忆/等级时按默认值走
    func streamReply(
        for character: Character,
        history: [ChatMessage],
        userText: String
    ) -> AsyncThrowingStream<String, Error> {
        streamReply(for: character, history: history, userText: userText, level: 1, memory: [])
    }
}

/// 本地模拟：PersonaEngine 按角色性格生成回复，逐字吐字，支持取消与失败注入。
/// 接真 LLM 时整体替换为 SSE 实现，UI 层零改动。
struct MockChatService: ChatService {
    var firstTokenDelay: Duration = .milliseconds(420)
    var chunkInterval: Duration = .milliseconds(34)
    /// 0 = 永不失败；演示时可调到 0.15 观察失败降级
    var failureRate: Double = 0

    func streamReply(
        for character: Character,
        history: [ChatMessage],
        userText: String,
        level: Int,
        memory: [MemoryTurn]
    ) -> AsyncThrowingStream<String, Error> {
        let reply = PersonaEngine.reply(
            for: character,
            history: history,
            userText: userText,
            intimacyLevel: level > 0 ? level : intimacyLevel(in: history)
        )
        let shouldFail = Double.random(in: 0..<1) < failureRate
        let delay = firstTokenDelay
        let interval = chunkInterval

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Task.sleep(for: delay)
                    if shouldFail { throw ChatError.timeout }
                    for chunk in reply.map({ String($0) }) {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                        try await Task.sleep(for: interval)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 从历史消息粗略估算亲密度等级（每 20 回合升 1 级）
    private func intimacyLevel(in history: [ChatMessage]) -> Int {
        let turns = history.filter { $0.role == .assistant }.count
        return 1 + turns / 20
    }
}
