import Foundation

// MARK: - 本地密钥（不进 Git）
//
// 仓库里只提交 `Config/LocalSecrets.example.json`（空值样例）；
// 真正带密钥的文件叫 `LocalSecrets.json`，已被 .gitignore 排除，只会打进你本机的 App 包。
//
// 没有这个文件、或字段为空 → 所有云服务自动降级为本地 Mock / 系统 TTS，
// clone 下来零配置就能跑；想接真模型再自己填。
enum LocalSecrets {

    /// 智谱 GLM（对话 + CogView 生图共用）
    static let zhipuAPIKey = value("zhipuAPIKey")

    /// 腾讯云语音合成
    static let tencentSecretId = value("tencentSecretId")
    static let tencentSecretKey = value("tencentSecretKey")

    static var hasAnyKey: Bool {
        !zhipuAPIKey.isEmpty || !tencentSecretId.isEmpty || !tencentSecretKey.isEmpty
    }

    private static let payload: [String: String] = {
        guard let url = Bundle.main.url(forResource: "LocalSecrets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return obj
    }()

    private static func value(_ key: String) -> String {
        (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
