import XCTest
@testable import AICompanion

/// 真实调用腾讯云语音合成，验证内置凭证可用（会消耗少量免费额度）
final class RealTencentTTSTests: XCTestCase {

    func testSynthesizeWithBundledCredentials() async throws {
        // 带上时间戳，确保不会命中本地缓存，真的走一次网络
        let text = "沈惊寒台词测试\(Int(Date().timeIntervalSince1970))"
        do {
            let url = try await TencentTTSClient.synthesize(text: text, kind: .deepMale)
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? Int) ?? 0
            print("TENCENT_TTS_OK size=\(size) path=\(url.lastPathComponent)")
            XCTAssertGreaterThan(size, 2000, "音频文件过小，可能不是有效 mp3")
        } catch {
            let msg = error.localizedDescription
            print("TENCENT_TTS_FAIL \(msg)")
            // 服务未开通/资源包未领 = 账号侧配置问题，不是代码问题，跳过而不是失败
            if msg.contains("未开通") || msg.contains("资源包") {
                throw XCTSkip("腾讯云服务尚未开通，跳过真实合成验证：\(msg)")
            }
            XCTFail("腾讯云语音调用失败：\(msg)")
        }
    }

    func testCredentialsAreConfigured() async {
        let configured = await MainActor.run { TencentVoiceSettings.shared.isConfigured }
        let usesBundled = await MainActor.run { TencentVoiceSettings.shared.usesBundledId }
        print("TENCENT_CREDS configured=\(configured) bundledId=\(usesBundled)")
        XCTAssertTrue(configured, "凭证未配置")
    }
}
