import Foundation

// MARK: - 一次性补全（非流式）

/// 用于人设生成等后台任务的简单补全调用，复用 LLMSettings 的服务商配置。
enum LLMClient {

    enum LLMError: LocalizedError {
        case notReady
        case badURL
        case http(Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .notReady: return "对话模型未启用或缺少 Key"
            case .badURL: return "服务地址无效"
            case .http(let code, let msg):
                if code == 401 { return "API Key 无效（401）" }
                if code == 429 { return "请求太频繁或额度不足（429）" }
                return "请求失败（\(code)）：\(msg.prefix(60))"
            case .badResponse: return "模型返回内容无法解析"
            }
        }
    }

    /// 非流式补全，返回模型第一段回复文本。
    @MainActor
    static func completeOnce(system: String, user: String, temperature: Double = 0.9) async throws -> String {
        let settings = LLMSettings.shared
        guard settings.isReady else { throw LLMError.notReady }
        var base = settings.baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/chat/completions") else { throw LLMError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        // 各厂商对 temperature 上限不一致（智谱限制 [0,1]，传 1.15 直接 400），这里统一夹紧
        let safeTemp = min(1.0, max(0.0, temperature))
        let body: [String: Any] = [
            "model": settings.model,
            "temperature": safeTemp,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw LLMError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String, !content.isEmpty else {
            throw LLMError.badResponse
        }
        return content
    }
}
