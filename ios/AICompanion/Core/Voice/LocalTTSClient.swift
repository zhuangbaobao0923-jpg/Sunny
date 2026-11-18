import Foundation

// MARK: - 本地 TTS 客户端

/// 调 Mac 上的本地 edge-tts 服务（127.0.0.1:9880）。
/// 该服务免费、无 Key、仅监听回环地址——App 侧不存在任何云端请求路径。
struct LocalTTSClient: Sendable {
    let baseURLString: String
    let session: URLSession

    init(baseURLString: String, session: URLSession = .shared) {
        self.baseURLString = baseURLString
        self.session = session
    }

    enum LocalTTSError: LocalizedError {
        case serverUnreachable(String)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case let .serverUnreachable(detail):
                return "本地语音服务未启动（\(detail)）。在 Mac 上运行 bash ios/tools/start-tts.sh"
            case let .badResponse(detail):
                return "本地服务响应异常：\(detail)"
            }
        }
    }

    /// 服务健康检查
    func health() async throws {
        guard let url = URL(string: baseURLString + "/health") else {
            throw LocalTTSError.badResponse("地址无效")
        }
        var request = URLRequest(url: url)
        // 局域网内本地服务响应 <100ms；超时几乎必然是 4G/断网场景，
        // 快速失败才能尽快降级到云端（15s 会让人以为语音坏了）
        request.timeoutInterval = 1.5
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] != nil else {
                throw LocalTTSError.badResponse("health 检查失败")
            }
        } catch let error as LocalTTSError {
            throw error
        } catch {
            throw LocalTTSError.serverUnreachable(error.localizedDescription)
        }
    }

    /// 合成语音，返回 mp3 数据
    func synthesize(
        text: String,
        voice: String,
        rate: String,
        pitch: String
    ) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURLString + "/tts")!)
        request.httpMethod = "POST"
        // 家中局域网正常合成 1~3s；4G 下这个请求注定失败，
        // 8s 超时让降级到云端的等待控制在可感知范围内
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "voice": voice,
            "rate": rate,
            "pitch": pitch
        ])

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LocalTTSError.badResponse("无响应")
            }
            guard (200..<300).contains(http.statusCode), !data.isEmpty else {
                let detail = String(data: data.prefix(160), encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw LocalTTSError.badResponse(detail)
            }
            return data
        } catch let error as LocalTTSError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            // 用户切到别的音色/台词导致请求取消：属于正常中断，不当成服务故障
            throw CancellationError()
        } catch {
            throw LocalTTSError.serverUnreachable(error.localizedDescription)
        }
    }
}

// MARK: - 本地合成缓存（同一句台词 + 同一音色只合成一次）

actor LocalTTSAudioCache {
    static let shared = LocalTTSAudioCache()

    private var memory: [String: URL] = [:]
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("VoiceCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func audioURL(text: String, voice: String, rate: String, pitch: String, client: LocalTTSClient) async throws -> URL {
        let key = Self.key(text: text, voice: voice, rate: rate, pitch: pitch)
        if let cached = memory[key], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        let file = directory.appendingPathComponent(key + ".mp3")
        if FileManager.default.fileExists(atPath: file.path) {
            memory[key] = file
            return file
        }
        let data = try await client.synthesize(text: text, voice: voice, rate: rate, pitch: pitch)
        try data.write(to: file, options: .atomic)
        memory[key] = file
        trimIfNeeded()
        return file
    }

    /// 稳定缓存键：FNV-1a，跨启动一致
    static func key(text: String, voice: String, rate: String, pitch: String) -> String {
        fnv1a("\(voice)|\(rate)|\(pitch)|\(text)")
    }

    static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    private func trimIfNeeded() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ), files.count > 120 else { return }
        let sorted = files.sorted {
            let a = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let b = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (a ?? .distantPast) < (b ?? .distantPast)
        }
        for file in sorted.prefix(files.count - 100) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
