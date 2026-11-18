import XCTest
@testable import AICompanion

/// 腾讯云 TC3 签名与音色映射
final class TencentTTSTests: XCTestCase {

    func testSignatureFormatAndDeterminism() throws {
        let a = try TencentTTSClient.sign(
            body: #"{"Text":"你好"}"#, timestamp: 1_700_000_000,
            secretId: "AKIDTEST1234567890", secretKey: "TESTKEY1234567890"
        )
        let b = try TencentTTSClient.sign(
            body: #"{"Text":"你好"}"#, timestamp: 1_700_000_000,
            secretId: "AKIDTEST1234567890", secretKey: "TESTKEY1234567890"
        )
        XCTAssertEqual(a.authorization, b.authorization, "同一输入必须得到同一签名")
        XCTAssertTrue(a.authorization.hasPrefix("TC3-HMAC-SHA256 Credential=AKIDTEST1234567890/"))
        XCTAssertTrue(a.authorization.contains("/tts/tc3_request"))
        XCTAssertTrue(a.authorization.contains("SignedHeaders=content-type;host"))
        // 签名是 64 位十六进制
        let sig = a.authorization.components(separatedBy: "Signature=").last ?? ""
        XCTAssertEqual(sig.count, 64)
        XCTAssertTrue(sig.allSatisfy { $0.isHexDigit })
    }

    func testSignatureChangesWithBody() throws {
        let a = try TencentTTSClient.sign(
            body: #"{"Text":"你好"}"#, timestamp: 1_700_000_000,
            secretId: "id", secretKey: "key"
        )
        let b = try TencentTTSClient.sign(
            body: #"{"Text":"再见"}"#, timestamp: 1_700_000_000,
            secretId: "id", secretKey: "key"
        )
        XCTAssertNotEqual(a.authorization, b.authorization)
    }

    /// 14 种角色音色必须全部落到合法的腾讯云音色 id 与语速范围
    func testVoiceMappingCoversAllKinds() {
        for kind in VoiceKind.allCases {
            XCTAssertGreaterThanOrEqual(kind.tencentVoiceType, 101001, "\(kind.rawValue) 音色 id 异常")
            XCTAssertLessThanOrEqual(kind.tencentVoiceType, 101099, "\(kind.rawValue) 音色 id 异常")
            XCTAssertTrue((-2...2).contains(kind.tencentSpeed), "\(kind.rawValue) 语速越界")
        }
        // 男女角色不应共用同一音色
        XCTAssertNotEqual(VoiceKind.deepMale.tencentVoiceType, VoiceKind.softGirl.tencentVoiceType)
    }
}
