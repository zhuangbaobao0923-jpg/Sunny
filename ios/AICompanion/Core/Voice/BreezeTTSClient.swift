import Foundation
import Observation

// MARK: - 角色 → BreezeBlue 音色
//
// 现有 5 个种子角色按 ID 精确映射；用户新建角色按 VoiceKind 兜底。
// 只映射“气质确定”的音色，没把握的返回 nil，回退到原有引擎，避免乱配。

enum BreezeVoiceCast {
    struct Entry: Sendable, Equatable {
        let name: String
        let voiceID: String
        let speed: Double

        init(name: String, voiceID: String, speed: Double = 1.0) {
            self.name = name
            self.voiceID = voiceID
            self.speed = speed
        }
    }

    static let byCharacterID: [String: Entry] = [
        "sjh": Entry(name: "幽巷引路人", voiceID: "voc_gbaz4j9uyq97"),
        "nlz": Entry(name: "青史执笔人", voiceID: "voc_3nw7zw44cxek"),
        "swt": Entry(name: "大肥鱼·迷糊版", voiceID: "voc_8yud7hz7c9q2"),
        "xwj": Entry(name: "深海低语者", voiceID: "voc_mtb2gb2f565z"),
        "lyc": Entry(name: "冷面铁捕", voiceID: "voc_4fcdc882gyps", speed: 0.95),
    ]

    /// 音色名 → Entry：直接由 VoiceCatalog 生成，保证与创建页选项一一对应
    static let byVoiceName: [String: Entry] = Dictionary(
        uniqueKeysWithValues: VoiceCatalog.all.map {
            ($0.name, Entry(name: $0.name, voiceID: $0.voiceID, speed: $0.speed))
        }
    )

    /// 同名兜底：云端发布的同名角色 id 不是 "swt"，但名字仍是「苏晚棠」
    static let byCharacterName: [String: Entry] = [
        "沈惊寒": Entry(name: "幽巷引路人", voiceID: "voc_gbaz4j9uyq97"),
        "纳兰铮": Entry(name: "青史执笔人", voiceID: "voc_3nw7zw44cxek"),
        "苏晚棠": Entry(name: "大肥鱼·迷糊版", voiceID: "voc_8yud7hz7c9q2"),
        "谢无咎": Entry(name: "深海低语者", voiceID: "voc_mtb2gb2f565z"),
        "凌云裳": Entry(name: "冷面铁捕", voiceID: "voc_4fcdc882gyps", speed: 0.95),
    ]

    /// 兼容旧调用点
    static var byName: [String: Entry] { byVoiceName }

    static let byVoiceKind: [VoiceKind: Entry] = [
        .warmFemale: Entry(name: "大肥鱼·偶像版", voiceID: "voc_rn489h83rcvs"),
        .elegantFemale: Entry(name: "凤仪（皇后）", voiceID: "voc_psyuun5rky74"),
        .livelyGirl: Entry(name: "大肥鱼·机灵版", voiceID: "voc_u3nxkd5578wc"),
        .softGirl: Entry(name: "大肥鱼·迷糊版", voiceID: "voc_8yud7hz7c9q2"),
        .sweetGirl: Entry(name: "大肥鱼·破晓版", voiceID: "voc_d7fhsuhdaptx"),
        .deepMale: Entry(name: "幽巷引路人", voiceID: "voc_gbaz4j9uyq97"),
        .magneticMale: Entry(name: "深海低语者", voiceID: "voc_mtb2gb2f565z"),
        .broadcastMale: Entry(name: "醇厚匠心师", voiceID: "voc_aa4s73p25jt2"),
    ]

    static func entry(for character: Character) -> Entry? {
        // 1. 种子角色按 id；2. 角色自己选的音色名；3. 云端同名角色；4. 按音色类型兜底
        if let byID = byCharacterID[character.id] { return byID }
        if let picked = byVoiceName[character.voiceName ?? ""] { return picked }
        if let byNameHit = byCharacterName[character.name] { return byNameHit }
        return byVoiceKind[character.voiceKind]
    }
}

// MARK: - 凭证（Keychain）

@MainActor
@Observable
final class BreezeVoiceSettings {
    static let shared = BreezeVoiceSettings()

    private let keyAccount = "breeze.tts.apiKey"
    private let enabledKey = "breeze.tts.enabled"

    private var storedKey: String

    /// 聊天语音条是否优先用 BreezeBlue；关闭后完全不发请求
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: enabledKey) }
    }

    private init() {
        var key = Keychain.get(keyAccount)
        #if DEBUG
        // 仅调试：允许用环境变量注入 Key 做模拟器自检，不写入 Keychain、不进代码库
        if key.isEmpty,
           let env = ProcessInfo.processInfo.environment["BREEZE_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            key = env
        }
        #endif
        storedKey = key
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            enabled = true
        } else {
            enabled = UserDefaults.standard.bool(forKey: enabledKey)
        }
    }

    /// 界面上只显示“是否已填”，不回显明文
    var hasKey: Bool {
        !storedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isConfigured: Bool { hasKey && enabled }

    var apiKey: String {
        storedKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func save(key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return hasKey }
        storedKey = trimmed
        Keychain.set(trimmed, for: keyAccount)
        enabled = true
        return true
    }

    func clear() {
        storedKey = ""
        Keychain.set("", for: keyAccount)
    }
}

// MARK: - 合成

enum BreezeTTSClient {
    enum TTSError: LocalizedError {
        case notConfigured
        case emptyText
        case badResponse(Int, String)
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "BreezeBlue 未配置 API Key"
            case .emptyText: return "文本为空"
            case .badResponse(let code, let message):
                if code == 401 || code == 403 { return "BreezeBlue 鉴权失败（HTTP \(code)）" }
                if code == 402 { return "BreezeBlue 额度不足（HTTP 402）" }
                if code == 429 { return "BreezeBlue 限流（HTTP 429）" }
                return "BreezeBlue 返回 HTTP \(code)：\(message.prefix(80))"
            case .emptyAudio: return "BreezeBlue 未返回音频"
            }
        }
    }

    private static let baseURL = "https://api.breeze.blue"

    /// 合成并落盘；同音色、同语速、同文本命中缓存，不重复计费。
    static func synthesize(text: String, entry: BreezeVoiceCast.Entry) async throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TTSError.emptyText }

        let key = await MainActor.run { BreezeVoiceSettings.shared.apiKey }
        guard !key.isEmpty else { throw TTSError.notConfigured }

        let cacheKey = cacheKey(text: trimmed, entry: entry)
        if let cached = AudioFileCache.existing(key: cacheKey) { return cached }

        guard var comps = URLComponents(string: "\(baseURL)/v1/text-to-speech/\(entry.voiceID)") else {
            throw TTSError.badResponse(0, "invalid url")
        }
        comps.queryItems = [
            URLQueryItem(name: "output_format", value: "mp3_24000_128"),
            URLQueryItem(name: "delivery", value: "sync"),
        ]
        guard let url = comps.url else { throw TTSError.badResponse(0, "invalid url") }

        var payload: [String: Any] = [
            "text": trimmed,
            "language_code": "zh",
        ]
        if entry.speed != 1.0 {
            payload["voice_settings"] = ["speed": entry.speed]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TTSError.badResponse(0, "no response")
        }
        guard http.statusCode == 200 else {
            let message = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw TTSError.badResponse(http.statusCode, message)
        }
        guard data.count > 1024 else { throw TTSError.emptyAudio }

        return try AudioFileCache.persist(data, key: cacheKey, ext: "mp3")
    }

    // MARK: 流式与缓存

    static func cacheKey(text: String, entry: BreezeVoiceCast.Entry) -> String {
        "breeze|\(entry.voiceID)|\(entry.speed)|\(text)"
    }

    static func cachedAudio(text: String, entry: BreezeVoiceCast.Entry) -> URL? {
        AudioFileCache.existing(key: cacheKey(text: text, entry: entry))
    }

    /// 流式请求：PCM 24 kHz / 16-bit / 单声道，边生成边播。
    @MainActor
    static func makeStreamRequest(text: String, entry: BreezeVoiceCast.Entry) throws -> URLRequest {
        let key = BreezeVoiceSettings.shared.apiKey
        guard !key.isEmpty else { throw TTSError.notConfigured }
        guard var comps = URLComponents(string: "\(baseURL)/v1/text-to-speech/\(entry.voiceID)/stream") else {
            throw TTSError.badResponse(0, "invalid url")
        }
        comps.queryItems = [URLQueryItem(name: "output_format", value: "pcm")]
        guard let url = comps.url else { throw TTSError.badResponse(0, "invalid url") }

        var payload: [String: Any] = [
            "text": text,
            "language_code": "zh",
        ]
        if entry.speed != 1.0 {
            payload["voice_settings"] = ["speed": entry.speed]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// 把流式 PCM 补 44 字节 WAV 头存进缓存，下次点同一条直接播，不再计费。
    static func saveWAV(pcm: Data, text: String, entry: BreezeVoiceCast.Entry) {
        guard !pcm.isEmpty else { return }
        let wav = wavData(from: pcm)
        _ = try? AudioFileCache.persist(wav, key: cacheKey(text: text, entry: entry), ext: "wav")
    }

    private static func wavData(from pcm: Data) -> Data {
        let sampleRate: UInt32 = 24_000
        let channels: UInt16 = 1
        let bits: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bits / 8)
        let blockAlign = channels * (bits / 8)
        let dataSize = UInt32(pcm.count)

        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(le32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(le32(16))
        data.append(le16(1))
        data.append(le16(channels))
        data.append(le32(sampleRate))
        data.append(le32(byteRate))
        data.append(le16(blockAlign))
        data.append(le16(bits))
        data.append(contentsOf: Array("data".utf8))
        data.append(le32(dataSize))
        data.append(pcm)
        return data
    }

    private static func le16(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func le32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}

#if DEBUG
// 仅模拟器自检：启动参数 -BreezeSelfTest 时，用苏晚棠说一句并落一份结果文件。
enum BreezeSelfTest {
    @MainActor
    static func runIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-BreezeSelfTest") else { return }
        var log = ""
        for option in SampleData.voiceOptions {
            let entry = BreezeVoiceCast.byName[option.name]
            log += "option=\(option.name) kind=\(VoiceKind.kind(for: option.name).rawValue) breeze=\(entry?.voiceID ?? "nil")\n"
        }
        guard let character = SampleData.characters.first(where: { $0.id == "swt" }) else {
            write("engine=nil\nerror=no character swt\n")
            return
        }
        NSLog("BREEZE_SELFTEST start key=%@", BreezeVoiceSettings.shared.hasKey ? "yes" : "no")

        let t0 = Date()
        VoiceService.shared.speak("嗯，对啊，这是我最大的梦想。虽然路上可能会有很多困难，但我不会放弃的！你呢，你有什么梦想？", for: character)

        var ttfa: TimeInterval?
        for _ in 0..<120 {
            try? await Task.sleep(for: .milliseconds(100))
            if ttfa == nil, !VoiceService.shared.isPreparing {
                ttfa = Date().timeIntervalSince(t0)
            }
            if VoiceService.shared.speakingID == nil && !VoiceService.shared.isPreparing { break }
        }
        let total = Date().timeIntervalSince(t0)
        let engine = VoiceService.shared.lastEngine
        let error = VoiceService.shared.lastBreezeError ?? VoiceService.shared.lastError ?? "nil"
        NSLog("BREEZE_SELFTEST engine=%@ ttfa=%.2f total=%.2f error=%@", engine, ttfa ?? -1, total, error)
        log += String(format: "ttfa=%.2f\ntotal=%.2f\n", ttfa ?? -1, total)
        log += "engine=\(engine)\nerror=\(error)\nkey=\(BreezeVoiceSettings.shared.hasKey ? "yes" : "no")\n"
        write(log)
    }

    private static func write(_ text: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("breeze_selftest.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif
