import Foundation
import Observation

// MARK: - 微软 Azure 神经语音（云扬等，F0 每月 50 万字符免费）

/// 官方 REST 接口，SSML 控制音高/语速。
/// 选它是因为「云扬」这类中文神经音色的自然度明显高于基础版云 TTS，
/// 且手机在 4G / Wi-Fi 下都能直连，不依赖 Mac。
enum AzureTTSClient {

    enum TTSError: LocalizedError {
        case notConfigured
        case badURL
        case api(String)
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "未填写 Azure 语音服务 Key"
            case .badURL: return "Azure 区域填写有误"
            case .api(let msg): return "Azure 语音失败：\(msg)"
            case .emptyAudio: return "Azure 未返回音频"
            }
        }
    }

    static func synthesize(text: String, kind: VoiceKind) async throws -> URL {
        let cfg = await MainActor.run { AzureVoiceSettings.shared.config }
        guard let cfg else { throw TTSError.notConfigured }

        let voice = kind.azureVoice
        let pitch = kind.azurePitchPercent
        let rate = kind.azureRatePercent
        let cacheKey = "az|\(voice)|\(pitch)|\(rate)|\(text)"
        if let cached = AudioFileCache.existing(key: cacheKey) { return cached }

        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let ssml = """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>\
        <voice name='\(voice)'><prosody pitch='\(pitch)' rate='\(rate)'>\(escaped)</prosody></voice></speak>
        """

        guard let url = URL(string: "https://\(cfg.region).tts.speech.microsoft.com/cognitiveservices/v1") else {
            throw TTSError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = Data(ssml.utf8)
        request.setValue(cfg.key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("nightTalk", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await sendWithRetry(request)
        guard let http = response as? HTTPURLResponse else { throw TTSError.api("无响应") }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8)?.prefix(120).description ?? "未知错误"
            throw TTSError.api("HTTP \(http.statusCode)｜\(msg)")
        }
        guard data.count > 512 else { throw TTSError.emptyAudio }
        return try AudioFileCache.persist(data, key: cacheKey, ext: "mp3")
    }

    /// 蜂窝网络偶发丢包：失败重试一次
    private static func sendWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            try? await Task.sleep(for: .milliseconds(600))
            return try await URLSession.shared.data(for: request)
        }
    }
}

// MARK: - 凭证

@MainActor
@Observable
final class AzureVoiceSettings {
    static let shared = AzureVoiceSettings()

    private let keyAccount = "azure.speech.key"
    private let regionAccount = "azure.speech.region"

    private var storedKey: String
    private(set) var region: String

    private init() {
        storedKey = Keychain.get(keyAccount)
        let saved = Keychain.get(regionAccount)
        region = saved.isEmpty ? "eastasia" : saved
    }

    struct Config: Sendable {
        let key: String
        let region: String
    }

    var isConfigured: Bool {
        !storedKey.trimmingCharacters(in: .whitespaces).isEmpty && !region.isEmpty
    }

    var hasKey: Bool { isConfigured }

    var config: Config? {
        guard isConfigured else { return nil }
        return Config(key: storedKey.trimmingCharacters(in: .whitespaces), region: region)
    }

    func save(key: String, region: String) {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            storedKey = trimmedKey
            Keychain.set(trimmedKey, for: keyAccount)
        }
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRegion.isEmpty {
            self.region = trimmedRegion
            Keychain.set(trimmedRegion, for: regionAccount)
        }
    }

    func clear() {
        storedKey = ""
        Keychain.set("", for: keyAccount)
    }
}

// MARK: - 角色音色 → Azure 神经音色

extension VoiceKind {
    var azureVoice: String {
        switch self {
        case .sunnyMale, .clearYoungMale, .boyish: return "zh-CN-YunxiNeural"
        case .deepMale, .magneticMale, .broadcastMale: return "zh-CN-YunyangNeural"
        case .warmFemale, .elegantFemale: return "zh-CN-XiaoxiaoNeural"
        case .livelyGirl, .softGirl: return "zh-CN-XiaoyiNeural"
        case .cartoonBoy: return "zh-CN-YunxiaNeural"
        case .sweetGirl: return "zh-CN-XiaoshuangNeural"
        case .dongbeiAunt: return "zh-CN-liaoning-XiaobeiNeural"
        case .shaanxiFemale: return "zh-CN-shaanxi-XiaoniNeural"
        }
    }

    /// SSML prosody pitch（相对百分比）
    var azurePitchPercent: String {
        switch self {
        case .deepMale: return "-16%"
        case .magneticMale: return "-22%"
        case .clearYoungMale: return "-8%"
        case .sunnyMale: return "-4%"
        case .boyish: return "+8%"
        case .elegantFemale: return "-5%"
        case .livelyGirl: return "+8%"
        case .softGirl: return "-4%"
        case .cartoonBoy: return "+4%"
        case .sweetGirl: return "+18%"
        case .dongbeiAunt: return "+2%"
        default: return "0%"
        }
    }

    /// SSML prosody rate（相对百分比）
    var azureRatePercent: String {
        switch self {
        case .deepMale: return "-15%"
        case .magneticMale: return "-20%"
        case .clearYoungMale: return "-10%"
        case .sunnyMale: return "-5%"
        case .boyish: return "+4%"
        case .warmFemale: return "-5%"
        case .elegantFemale: return "-10%"
        case .softGirl: return "-3%"
        default: return "0%"
        }
    }
}
