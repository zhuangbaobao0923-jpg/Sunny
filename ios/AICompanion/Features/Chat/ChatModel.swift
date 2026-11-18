import Observation
import SwiftUI

@MainActor
@Observable
final class ChatModel {
    let character: Character

    private(set) var messages: [ChatMessage] = []
    private(set) var isStreaming = false
    private(set) var isWaitingFirstToken = false
    private(set) var intimacy = IntimacyProgress()
    private(set) var likeCount: Int
    private(set) var liked: Bool

    var input: String = ""
    var showLevelUp = false
    var lastError: String?
    /// 回合成功结束的钩子（语音通话页用来拿最终回复做朗读）；参数 = AI 最终回复全文
    var onReplyFinished: ((String) -> Void)?

    private let service: ChatService
    private var streamTask: Task<Void, Never>?
    private var lastUserText: String?

    /// 上下文窗口：只回传最近 20 回合给服务端（更早内容在服务端摘要压缩）
    private static let historyWindow = 20

    init(character: Character, service: ChatService) {
        self.character = character
        self.service = service
        self.likeCount = character.likeCount
        self.liked = character.liked
        restoreOrSeed()
    }

    /// 有历史 → 原样恢复聊天记录和等级；无历史 → 72h 承接问候或开场白
    private func restoreOrSeed() {
        if let snapshot = ChatHistoryStorage.load(characterID: character.id),
           !snapshot.messages.isEmpty {
            messages = snapshot.messages.map { saved in
                ChatMessage(role: saved.role == "user" ? .user : .assistant, text: saved.text, date: saved.date)
            }
            intimacy = IntimacyProgress(rounds: snapshot.rounds)
            likeCount = snapshot.likeCount
            liked = snapshot.liked
            return
        }
        seedOpening()
    }

    /// 把当前聊天记录 + 亲密度 + 点赞写入本地（每次成功回合 / 点赞后调用）
    func persist() {
        let snapshot = ChatHistoryStorage.snapshot(
            messages: messages,
            rounds: intimacy.rounds,
            likeCount: likeCount,
            liked: liked
        )
        guard !snapshot.messages.isEmpty else { return }
        ChatHistoryStorage.save(snapshot, characterID: character.id)
    }

    var canSend: Bool {
        !isStreaming && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var voiceUnlocked: Bool { intimacy.voiceUnlocked }

    private func seedOpening() {
        // 跨会话接续：72 小时内回来过 → 首句主动承接上次话题（严禁当新用户）
        // 超 72 小时 → 模糊记忆问候；从未聊过 → 正常开场白
        if let greeting = PersonaEngine.returnGreeting(for: character) {
            messages = [.assistant(greeting)]
        } else {
            messages = [.assistant(character.opening)]
        }
    }

    // MARK: - 发送

    /// 语音通话的招呼语写入聊天记录（保持上下文连贯），不动流式状态
    func appendCallGreeting(_ text: String) {
        guard !text.isEmpty else { return }
        if let index = messages.indices.last, messages[index].role == .assistant && messages[index].text == text {
            return
        }
        messages.append(.assistant(text))
        persist()
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        input = ""
        lastError = nil
        messages.append(.user(text))
        lastUserText = text
        startStream(replyingTo: text)
    }

    func retry() {
        guard let text = lastUserText, !isStreaming else { return }
        messages.removeAll { $0.failed }
        lastError = nil
        startStream(replyingTo: text)
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        isWaitingFirstToken = false
        if let index = messages.indices.last, messages[index].streaming {
            messages[index].streaming = false
            if messages[index].text.isEmpty {
                messages.remove(at: index)
            }
        }
    }

    private func startStream(replyingTo text: String) {
        isStreaming = true
        isWaitingFirstToken = true
        let history = Array(messages.suffix(Self.historyWindow))
        // 人设 + 亲密度 + 跨会话记忆一起交给引擎（Mock 与真模型走同一套上下文）
        let stream = service.streamReply(
            for: character,
            history: history,
            userText: text,
            level: intimacy.level,
            memory: ChatMemoryStore.shared.turns(for: character.id)
        )

        streamTask = Task { [weak self] in
            guard let self else { return }
            var buffer = ""
            var assistantIndex: Int?
            do {
                for try await chunk in stream {
                    try Task.checkCancellation()
                    if assistantIndex == nil {
                        self.isWaitingFirstToken = false
                        self.messages.append(.assistant("", streaming: true))
                        assistantIndex = self.messages.count - 1
                    }
                    buffer += chunk
                    if let index = assistantIndex {
                        self.messages[index].text = buffer
                    }
                }
                self.finishStream(assistantIndex: assistantIndex, error: nil)
            } catch is CancellationError {
                self.finishStream(assistantIndex: assistantIndex, error: nil)
            } catch {
                self.finishStream(assistantIndex: assistantIndex, error: error)
            }
        }
    }

    private func finishStream(assistantIndex: Int?, error: Error?) {
        if let index = assistantIndex, messages.indices.contains(index) {
            messages[index].streaming = false
            if messages[index].text.isEmpty {
                messages.remove(at: index)
            }
        }

        if let error {
            let reason = (error as? ChatError)?.errorDescription ?? error.localizedDescription
            lastError = reason
            messages.append(.failure("\(reason)，点击重试"))
        } else {
            recordTurn()
            persist()
            recordMemory()
            let reply = messages.last(where: { $0.role == .assistant && !$0.failed })?.text
            if let reply, !reply.isEmpty {
                onReplyFinished?(reply)
            }
        }

        isStreaming = false
        isWaitingFirstToken = false
        streamTask = nil
    }

    /// 一次成功的一问一答 = 1 回合
    private func recordTurn() {
        guard messages.contains(where: { $0.role == .assistant && !$0.failed }) else { return }
        if intimacy.recordTurn() {
            withAnimation(Motion.smooth) { showLevelUp = true }
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1900))
                withAnimation(.easeOut(duration: 0.4)) { self?.showLevelUp = false }
            }
        }
    }

    /// 记录跨会话记忆（Mock 与真实模型共用；下次进来自动承接）
    private func recordMemory() {
        guard let user = lastUserText,
              let reply = messages.last(where: { $0.role == .assistant && !$0.failed })?.text,
              !user.isEmpty, !reply.isEmpty else { return }
        ChatMemoryStore.shared.record(characterID: character.id, user: user, reply: reply)
    }

    // MARK: - 点赞

    func toggleLike() {
        liked.toggle()
        likeCount += liked ? 1 : -1
        persist()
    }
}
