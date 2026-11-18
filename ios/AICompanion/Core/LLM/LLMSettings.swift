import Foundation
import Observation

// MARK: - 模型服务商预设

/// 全部走 OpenAI 兼容协议（/chat/completions + SSE 流式），换厂商只改地址和模型名。
enum LLMProvider: String, CaseIterable, Identifiable {
    case zhipu
    case deepseek
    case dashscope
    case moonshot
    case ollama
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zhipu: return "智谱 GLM（有免费模型）"
        case .deepseek: return "DeepSeek"
        case .dashscope: return "阿里云百炼"
        case .moonshot: return "Kimi / Moonshot"
        case .ollama: return "本机 Ollama（全离线）"
        case .custom: return "自定义（OpenAI 兼容）"
        }
    }

    var shortTitle: String {
        switch self {
        case .zhipu: return "智谱"
        case .deepseek: return "DeepSeek"
        case .dashscope: return "百炼"
        case .moonshot: return "Kimi"
        case .ollama: return "本机"
        case .custom: return "自定义"
        }
    }

    var baseURL: String {
        switch self {
        case .zhipu: return "https://open.bigmodel.cn/api/paas/v4"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .dashscope: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .moonshot: return "https://api.moonshot.cn/v1"
        case .ollama: return "http://192.168.1.10:11434/v1"   // 改成 Mac 局域网 IP
        case .custom: return ""
        }
    }

    var model: String {
        switch self {
        case .zhipu: return "glm-4-flash"
        case .deepseek: return "deepseek-chat"
        case .dashscope: return "qwen-flash"
        case .moonshot: return "moonshot-v1-8k"
        case .ollama: return "qwen2.5:7b"
        case .custom: return ""
        }
    }

    /// 是否需要 API Key（本机 Ollama 不需要）
    var needsKey: Bool { self != .ollama }

    var note: String {
        switch self {
        case .zhipu: return "glm-4-flash 目前免费，注册后在控制台创建 API Key 即可"
        case .deepseek: return "按量计费，价格很低；需在开放平台创建 Key"
        case .dashscope: return "qwen-flash 有免费额度；百炼控制台创建 Key"
        case .moonshot: return "按量计费；开放平台创建 Key"
        case .ollama: return "Mac 上 ollama serve 后填局域网地址，不联网、不花钱、不填 Key"
        case .custom: return "任意 OpenAI 兼容服务：填 /v1 结尾的地址与模型名"
        }
    }

    var needsManualBaseURL: Bool { self == .ollama || self == .custom }
}

// MARK: - 模型配置（不可变快照，跨线程安全）

struct LLMConfig: Sendable, Equatable {
    var baseURL: String
    var model: String
    var apiKey: String
    var temperature: Double = 0.85

    var isUsable: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var chatCompletionsURL: URL? {
        var text = baseURL.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text + "/chat/completions")
    }
}

// MARK: - 设置存储

@MainActor
@Observable
final class LLMSettings {
    static let shared = LLMSettings()

    private let defaults = UserDefaults.standard
    private let providerKey = "llm.provider"
    private let baseURLKey = "llm.baseURL"
    private let modelKey = "llm.model"
    private let enabledKey = "llm.enabled"
    private let keychainAccount = "llm.apiKey"

    /// 用户是否启用真实模型（关掉则回到本地人设 Mock，保证随时能演示）
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: enabledKey) }
    }

    var provider: LLMProvider {
        didSet {
            defaults.set(provider.rawValue, forKey: providerKey)
            if provider != .custom {
                baseURL = provider.baseURL
                model = provider.model
            }
        }
    }

    var baseURL: String {
        didSet { defaults.set(baseURL, forKey: baseURLKey) }
    }

    var model: String {
        didSet { defaults.set(model, forKey: modelKey) }
    }

    var apiKey: String {
        didSet { Keychain.set(apiKey, for: keychainAccount) }
    }

    private init() {
        let storedProvider = LLMProvider(rawValue: defaults.string(forKey: providerKey) ?? "") ?? .zhipu
        provider = storedProvider
        baseURL = defaults.string(forKey: baseURLKey) ?? storedProvider.baseURL
        model = defaults.string(forKey: modelKey) ?? storedProvider.model
        let storedKey = Keychain.get(keychainAccount)
        // 用户从未自己填过 Key → 用本机 Config/LocalSecrets.json 里的（该文件不进 Git）；
        // 两者都没有 → 空 Key，isReady 为 false，App 自动走本地 Mock
        apiKey = storedKey.isEmpty ? LocalSecrets.zhipuAPIKey : storedKey
        isEnabled = defaults.bool(forKey: enabledKey)
        if !isEnabled && defaults.object(forKey: enabledKey) == nil {
            // 首次启动默认启用真实模型（失败会自动回落本地人设，不影响可用性）
            isEnabled = true
        }
    }

    /// 是否填了智谱 Key（生图同理）
    static var hasBundledKey: Bool { !LocalSecrets.zhipuAPIKey.isEmpty }

    /// 模型名可能是厂商刚上新的：允许手动改，这里只做基本校验
    var isReady: Bool {
        isEnabled && config.isUsable && (!provider.needsKey || !apiKey.isEmpty)
    }

    var config: LLMConfig {
        LLMConfig(baseURL: baseURL, model: model, apiKey: apiKey)
    }

    /// 生图专用配置：固定走智谱 CogView。
    /// 对话模型换成 DeepSeek / 百炼 / Kimi 后，那些服务的 /images/generations 并不存在，
    /// 生图会一直 404——表现就是「换一批永远是本地那几张占位图」，而聊天完全正常。
    var imageConfig: (baseURL: String, apiKey: String) {
        if provider == .zhipu, !apiKey.isEmpty, !baseURL.isEmpty {
            return (baseURL, apiKey)
        }
        return ("https://open.bigmodel.cn/api/paas/v4", LocalSecrets.zhipuAPIKey)
    }

    var statusText: String {
        if !isEnabled { return "当前为本地人设模式（Mock）" }
        if !config.isUsable { return "未填写服务地址或模型名" }
        if provider.needsKey && apiKey.isEmpty { return "缺少 API Key" }
        return "已接入 \(provider.shortTitle) · \(model)"
    }

    /// 各厂商 Key 申请入口（给设置页做说明）
    var consoleHint: String {
        switch provider {
        case .zhipu: return "open.bigmodel.cn → API Keys"
        case .deepseek: return "platform.deepseek.com → API keys"
        case .dashscope: return "bailian.console.aliyun.com → API-KEY"
        case .moonshot: return "platform.moonshot.cn → API Key 管理"
        case .ollama: return "先在 Mac 终端执行：ollama serve（模型：ollama pull qwen2.5:7b）"
        case .custom: return "按服务商文档填写"
        }
    }
}
