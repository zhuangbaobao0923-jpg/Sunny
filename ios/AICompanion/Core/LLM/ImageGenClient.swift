import UIKit
import Foundation

// MARK: - 智谱 CogView 文生图客户端（cogview-3-flash 免费）

/// 调用 OpenAI 兼容的 /images/generations 接口生成图片。
/// Key 与服务地址复用 LLMSettings（智谱 Key 同时可用于对话与生图）。
enum ImageGenClient {

    struct GenResult: Sendable {
        let localPath: String   // 下载后的本地文件路径（App Caches 下）
    }

    enum ImageGenError: LocalizedError {
        case noKey
        case badURL
        case http(Int, String)
        case emptyResponse
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .noKey: return "未配置 API Key"
            case .badURL: return "服务地址无效"
            case .http(let code, let msg):
                if code == 401 { return "API Key 无效（401）" }
                if code == 429 { return "请求太频繁或额度不足（429）" }
                return "生成失败（\(code)）：\(msg.prefix(60))"
            case .emptyResponse: return "服务未返回图片"
            case .downloadFailed: return "图片下载失败"
            }
        }
    }

    /// 生成一张图并落盘，返回本地路径。
    /// - Parameters:
    ///   - prompt: 中文描述（CogView 支持中文，无需翻译）
    ///   - size: 768x1344 竖版更适合角色立绘
    static func generate(_ prompt: String, size: String = "1024x1024") async throws -> GenResult {
        // 生图固定用智谱（CogView）：对话服务商不一定有 images 接口，
        // 直接用 LLMSettings.baseURL 会在换成 DeepSeek/百炼后稳定 404
        let (rawKey, rawBase) = await MainActor.run {
            let cfg = LLMSettings.shared.imageConfig
            return (cfg.apiKey, cfg.baseURL)
        }
        let key = rawKey.trimmingCharacters(in: .whitespaces)
        let base = rawBase.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw ImageGenError.noKey }

        var trimmed = base
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed + "/images/generations") else {
            throw ImageGenError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90      // 文生图较慢，给足时间
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": "cogview-3-flash",   // 智谱免费文生图模型
            "prompt": prompt,
            "size": size
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(httpCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ImageGenError.http(httpCode, msg)
        }

        // 响应结构：{"data":[{"url":"https://..."}]}
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]],
              let urlString = items.first?["url"] as? String,
              let imageURL = URL(string: urlString) else {
            throw ImageGenError.emptyResponse
        }

        let (imageData, dlResp) = try await URLSession.shared.data(from: imageURL)
        guard let dlCode = (dlResp as? HTTPURLResponse)?.statusCode, (200..<300).contains(dlCode),
              !imageData.isEmpty, UIImage(data: imageData) != nil else {
            throw ImageGenError.downloadFailed
        }
        return GenResult(localPath: try persist(imageData))
    }

    // MARK: - 本地缓存

    /// 生成图存到 Caches/generated-faces/，路径直接当作 imageName 传给各页面渲染。
    private static func persist(_ data: Data) throws -> String {
        let dir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("generated-faces", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "face-\(Int(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 100...999)).png"
        let fileURL = dir.appendingPathComponent(name)
        try data.write(to: fileURL, options: .atomic)
        return fileURL.path
    }
}
