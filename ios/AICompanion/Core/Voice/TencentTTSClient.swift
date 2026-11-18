import CryptoKit
import Foundation
import Observation

// MARK: - 腾讯云语音合成（免费 800 万字符额度，Wi-Fi / 蜂窝均可）

/// 官方接口 TextToVoice（Version 2019-08-23），TC3-HMAC-SHA256 签名。
/// 免费额度需在腾讯云控制台「语音合成」里领取（800 万字符，一个账号一次）。
enum TencentTTSClient {

    enum TTSError: LocalizedError {
        case notConfigured
        case badURL
        case api(String)
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "未填写腾讯云 SecretId / SecretKey"
            case .badURL: return "语音服务地址无效"
            case .api(let msg): return "腾讯云语音失败：\(msg)"
            case .emptyAudio: return "腾讯云未返回音频"
            }
        }
    }

    private static let host = "tts.tencentcloudapi.com"
    private static let service = "tts"
    private static let version = "2019-08-23"
    private static let region = "ap-guangzhou"

    /// 合成语音，返回落盘后的音频文件（同文本同音色命中缓存，不重复消耗额度）。
    static func synthesize(text: String, kind: VoiceKind) async throws -> URL {
        let creds = await MainActor.run { TencentVoiceSettings.shared.credentials }
        guard let creds else { throw TTSError.notConfigured }

        let cacheKey = "tx|\(kind.tencentVoiceType)|\(kind.tencentSpeed)|\(text)"
        if let cached = AudioFileCache.existing(key: cacheKey) { return cached }

        let payload: [String: Any] = [
            "Text": String(text.prefix(150)),
            "SessionId": UUID().uuidString.lowercased(),
            "VoiceType": kind.tencentVoiceType,
            "Codec": "mp3",
            "SampleRate": 16000,
            "Speed": kind.tencentSpeed,
            "Volume": 0,
            "ProjectId": 0,
            "ModelType": 1,
            "PrimaryLanguage": 1,
            "EnableSubtitle": false
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let bodyString = String(data: bodyData, encoding: .utf8) ?? "{}"

        var request = URLRequest(url: URL(string: "https://\(host)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let timestamp = Int(Date().timeIntervalSince1970)
        let signed = try sign(
            body: bodyString, timestamp: timestamp,
            secretId: creds.secretId, secretKey: creds.secretKey
        )
        request.httpBody = bodyData
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(signed.authorization, forHTTPHeaderField: "Authorization")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-TC-Timestamp")
        request.setValue(version, forHTTPHeaderField: "X-TC-Version")
        request.setValue(region, forHTTPHeaderField: "X-TC-Region")
        request.setValue("TextToVoice", forHTTPHeaderField: "X-TC-Action")
        request.setValue("ap-guangzhou", forHTTPHeaderField: "X-TC-Region")

        let (data, response) = try await sendWithRetry(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resp = json["Response"] as? [String: Any] else {
            throw TTSError.api(String(data: data, encoding: .utf8)?.prefix(80).description ?? "未知错误")
        }
        if let err = resp["Error"] as? [String: Any] {
            let msg = (err["Message"] as? String) ?? "未知错误"
            let code = (err["Code"] as? String) ?? ""
            return try reportAndThrow(code: code, message: msg)
        }
        guard let base64 = resp["Audio"] as? String,
              let audio = Data(base64Encoded: base64), audio.count > 512 else {
            throw TTSError.emptyAudio
        }
        return try AudioFileCache.persist(audio, key: cacheKey, ext: "mp3")
    }

    /// 蜂窝网络偶发丢包/首次 TLS 握手超时：失败后重试一次再决定是否降级
    private static func sendWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            try? await Task.sleep(for: .milliseconds(600))
            return try await URLSession.shared.data(for: request)
        }
    }

    private static func reportAndThrow(code: String, message: String) throws -> URL {
        let lower = message.lowercased()
        if lower.contains("not open") || message.contains("未开通") || code.contains("ServiceNotOpened") {
            throw TTSError.api("语音合成服务未开通：打开 console.cloud.tencent.com/tts 点「立即开通」，再领 800 万字符免费包")
        }
        if message.contains("资源包") || message.contains("欠费") || lower.contains("no free")
            || lower.contains("insufficient") || code.contains("NoFreeAmount") || code.contains("ResourceInsufficient") {
            throw TTSError.api("免费资源包未领取：在控制台「语音合成 → 资源包管理」领取 800 万字符")
        }
        if code.contains("AuthFailure") || lower.contains("signature") || lower.contains("secretid") {
            throw TTSError.api("SecretId / SecretKey 不正确或已禁用")
        }
        throw TTSError.api(message)
    }

    // MARK: - TC3-HMAC-SHA256 签名

    struct SignedRequest {
        let authorization: String
    }

    static func sign(body: String, timestamp: Int, secretId: String, secretKey: String) throws -> SignedRequest {
        let date = utcDate(timestamp)
        let contentType = "application/json; charset=utf-8"
        let canonicalHeaders = "content-type:\(contentType)\nhost:\(host)\n"
        let signedHeaders = "content-type;host"
        let hashedPayload = sha256Hex(body)
        let canonicalRequest = [
            "POST", "/", "", canonicalHeaders, signedHeaders, hashedPayload
        ].joined(separator: "\n")

        let credentialScope = "\(date)/\(service)/tc3_request"
        let stringToSign = [
            "TC3-HMAC-SHA256",
            String(timestamp),
            credentialScope,
            sha256Hex(canonicalRequest)
        ].joined(separator: "\n")

        let secretDate = hmac(key: Data(("TC3" + secretKey).utf8), message: date)
        let secretService = hmac(key: secretDate, message: service)
        let secretSigning = hmac(key: secretService, message: "tc3_request")
        let signature = hmac(key: secretSigning, message: stringToSign).map { String(format: "%02x", $0) }.joined()

        let authorization = "TC3-HMAC-SHA256 Credential=\(secretId)/\(credentialScope), "
            + "SignedHeaders=\(signedHeaders), Signature=\(signature)"
        return SignedRequest(authorization: authorization)
    }

    private static func utcDate(_ timestamp: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func hmac(key: Data, message: String) -> Data {
        let symmetric = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: symmetric)
        return Data(mac)
    }
}

// MARK: - 凭证存储（Keychain）

@MainActor
@Observable
final class TencentVoiceSettings {
    static let shared = TencentVoiceSettings()

    private let idAccount = "tencent.tts.secretId"
    private let keyAccount = "tencent.tts.secretKey"

    /// 内置凭证来自本机 Config/LocalSecrets.json（不进 Git）；用户自己填则优先。
    /// 都没有 → 不配置云端，VoiceService 自动降级到本地/系统 TTS。
    static var bundledSecretId: String { LocalSecrets.tencentSecretId }
    static var bundledSecretKey: String { LocalSecrets.tencentSecretKey }

    private let clearedKey = "tencent.tts.cleared"

    /// 用户手动填写的 SecretId（空 = 用内置）
    private var storedSecretId: String

    var secretId: String {
        get {
            let manual = storedSecretId.trimmingCharacters(in: .whitespaces)
            return manual.isEmpty ? Self.bundledSecretId : manual
        }
        set {
            storedSecretId = newValue
            Keychain.set(newValue, for: idAccount)
        }
    }

    /// SecretId 是否为内置值（界面据此显示「已内置」）
    var usesBundledId: Bool {
        storedSecretId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 出于安全，界面只展示是否已填写，不回显明文
    private(set) var hasSecretKey: Bool

    private var secretKey: String

    private init() {
        let storedId = Keychain.get(idAccount)
        let storedKey = Keychain.get(keyAccount)
        let userCleared = UserDefaults.standard.bool(forKey: clearedKey)
        let effectiveKey: String
        if !storedKey.isEmpty {
            effectiveKey = storedKey
        } else {
            effectiveKey = userCleared ? "" : Self.bundledSecretKey
        }
        storedSecretId = storedId
        secretKey = effectiveKey
        hasSecretKey = !effectiveKey.isEmpty
    }

    var isConfigured: Bool {
        !secretId.trimmingCharacters(in: .whitespaces).isEmpty && !secretKey.isEmpty
    }

    struct Credentials: Sendable {
        let secretId: String
        let secretKey: String
    }

    var credentials: Credentials? {
        guard isConfigured else { return nil }
        return Credentials(
            secretId: secretId.trimmingCharacters(in: .whitespaces),
            secretKey: secretKey
        )
    }

    func save(secretId: String, secretKey: String) {
        UserDefaults.standard.set(false, forKey: clearedKey)
        self.secretId = secretId.trimmingCharacters(in: .whitespaces)
        if !secretKey.isEmpty {
            self.secretKey = secretKey.trimmingCharacters(in: .whitespaces)
            hasSecretKey = true
            Keychain.set(self.secretKey, for: keyAccount)
        } else if self.secretKey.isEmpty {
            // 留空且原本没有：回落到内置凭证
            self.secretKey = Self.bundledSecretKey
            hasSecretKey = true
            Keychain.set("", for: keyAccount)
        }
    }

    func clear() {
        UserDefaults.standard.set(true, forKey: clearedKey)
        secretId = ""
        secretKey = ""
        hasSecretKey = false
        Keychain.set("", for: idAccount)
        Keychain.set("", for: keyAccount)
    }
}

// MARK: - 音频文件缓存（本地/云端共用，命中不重复消耗额度）

enum AudioFileCache {
    private static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("tts-audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func existing(key: String) -> URL? {
        // 早期版本写成 .audio、现在写 .mp3，两种都要认，否则缓存永远不命中
        for ext in ["mp3", "audio"] {
            let url = dir.appendingPathComponent(hash(key) + "." + ext)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static func persist(_ data: Data, key: String, ext: String) throws -> URL {
        let url = dir.appendingPathComponent(hash(key) + "." + ext)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// FNV-1a 64 位，避免文件名非法字符与冲突
    private static func hash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

// MARK: - 角色音色 → 腾讯云音色

extension VoiceKind {
    /// 腾讯云音色编号（精品音色，免费额度覆盖）。
    /// 编号对应的真实性别经 F0 基频实测校验——此前 deepMale 用的 101011 实为
    /// 「智燕·新闻女声」（198Hz），导致沈惊寒等男角色一直是女声，已全部更正。
    var tencentVoiceType: Int {
        switch self {
        case .sunnyMale: return 101004      // 智云：通用男声（167Hz，青年清亮）
        case .clearYoungMale: return 101030 // 智柯：通用男声（140Hz，自然清润）
        case .deepMale: return 101021       // 智瑞：新闻男声（105Hz，低沉厚重）
        case .magneticMale: return 101020   // 极低男声（93Hz，磁性大叔）
        case .broadcastMale: return 101013  // 智辉：新闻男声（116Hz，播音感）
        case .boyish: return 101010         // 智华（123Hz，少年感）
        case .warmFemale: return 101001     // 智瑜：情感女声（267Hz）
        case .livelyGirl: return 101026     // 智希（296Hz，明快）
        case .softGirl: return 101005       // 智莉：软糯少女（276Hz）
        case .elegantFemale: return 101002  // 智聆：知性冷静（267Hz）
        case .cartoonBoy: return 101015     // 智萌：男童声
        case .sweetGirl: return 101016      // 智甜：女童声（348Hz）
        case .dongbeiAunt: return 101009    // 智蓉（229Hz）
        case .shaanxiFemale: return 101027  // 智梅（242Hz）
        }
    }

    /// 腾讯云语速参数一律 0（原速）。
    /// 语速差异改由播放端 `cloudRate` 按实测值归一——云端 -2/+1 这种粗档位
    /// 会把「低沉男声」压到 3.9 字/秒、把「少年音」拉到 6.6 字/秒，一耳朵就不对。
    var tencentSpeed: Int { 0 }
}
