import Foundation

// MARK: - 真实模型（OpenAI 兼容 · SSE 流式）

/// 任何兼容 OpenAI Chat Completions 的服务都能用：智谱 / DeepSeek / 百炼 / Kimi / 本机 Ollama。
/// 只负责「把话问出去、把字流回来」，人格由 PersonaPrompt 注入。
struct RemoteChatService: ChatService {
    let config: LLMConfig

    enum LLMError: LocalizedError {
        case missingConfig
        case badURL
        case unauthorized
        case quota(String)
        case server(Int, String)
        case emptyReply

        var errorDescription: String? {
            switch self {
            case .missingConfig: return "模型未配置完整"
            case .badURL: return "服务地址格式不对（需要以 http:// 或 https:// 开头）"
            case .unauthorized: return "API Key 无效或已过期"
            case let .quota(detail): return "额度/限流问题：\(detail)"
            case let .server(code, detail): return "服务返回 \(code)：\(detail)"
            case .emptyReply: return "模型没有返回内容"
            }
        }
    }

    func streamReply(
        for character: Character,
        history: [ChatMessage],
        userText: String,
        level: Int,
        memory: [MemoryTurn]
    ) -> AsyncThrowingStream<String, Error> {
        let config = self.config

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard config.isUsable else { throw LLMError.missingConfig }
                    guard let url = config.chatCompletionsURL else { throw LLMError.badURL }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if !config.apiKey.isEmpty {
                        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                    }

                    let body: [String: Any] = [
                        "model": config.model,
                        "stream": true,
                        "temperature": config.temperature,
                        "messages": PersonaPrompt.messages(
                            for: character,
                            history: history,
                            userText: userText,
                            level: level,
                            memory: memory
                        )
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.server(-1, "无响应")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var detail = ""
                        for try await line in bytes.lines {
                            detail += line
                            if detail.count > 240 { break }
                        }
                        if http.statusCode == 401 || http.statusCode == 403 { throw LLMError.unauthorized }
                        if http.statusCode == 429 { throw LLMError.quota(detail.isEmpty ? "请求过于频繁" : detail) }
                        throw LLMError.server(http.statusCode, detail.isEmpty ? "请检查地址与模型名" : detail)
                    }

                    var yielded = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any] else { continue }
                        // 思维链模型（deepseek-r1 等）只取正文，跳过 reasoning_content
                        guard let content = delta["content"] as? String, !content.isEmpty else { continue }
                        yielded = true
                        continuation.yield(content)
                    }
                    if !yielded { throw LLMError.emptyReply }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - 连通性自检（设置页「测试连接」用）

enum LLMProbe {
    /// 发一句最短的请求，返回首个字，用来确认 Key / 地址 / 模型三项都对
    static func test(_ config: LLMConfig) async -> Result<String, Error> {
        let service = RemoteChatService(config: config)
        let character = Character(
            id: "probe", name: "测试", author: "@probe",
            imageName: "char_shenjinghan", tags: [], bio: "用于连通性测试",
            opening: "", replies: [], likeCount: 0, unread: 0,
            lastMessage: "", lastActivity: Date()
        )
        do {
            var first = ""
            for try await chunk in service.streamReply(
                for: character, history: [], userText: "只回复两个字：在的", level: 1, memory: []
            ) {
                first += chunk
                if first.count >= 12 { break }
            }
            return first.isEmpty ? .failure(RemoteChatService.LLMError.emptyReply) : .success(first)
        } catch {
            return .failure(error)
        }
    }
}
