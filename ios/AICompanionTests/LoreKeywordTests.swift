import XCTest
@testable import AICompanion

@MainActor
final class LoreKeywordTests: XCTestCase {

    func testParseArray() {
        let keys = LoreKeywordExpander.parse("""
        ```json
        ["工作","职业","上班","心理咨询"]
        ```
        """)
        XCTAssertEqual(keys.count, 4)
        XCTAssertTrue(keys.contains("工作"))
    }

    func testParseFiltersTooShortOrTooLong() {
        let keys = LoreKeywordExpander.parse("[\"工\",\"工作\",\"这是个特别特别长的句子不应该作为关键词\"]")
        XCTAssertEqual(keys, ["工作"])
    }

    func testFallbackUsesTitleAndSegments() {
        let keys = LoreKeywordExpander.fallback(title: "心理咨询师", content: "毕业后从事心理专业，喜欢倾听")
        XCTAssertTrue(keys.contains("心理咨询师"))
        XCTAssertTrue(keys.contains("毕业后从事心理专业") || keys.contains("喜欢倾听"))
    }

    /// 真实调用：和原人设直接矛盾时应该被识别出来
    func testConflictDetected() async throws {
        try XCTSkipUnless(LLMSettings.shared.isReady, "没配模型，跳过网络用例")
        let note = await LoreConflictChecker.check(
            content: "她毕业后做心理咨询师",
            bio: "苏晚棠的梦想是成为漫画家，一直在画漫画。"
        )
        XCTAssertNotNil(note, "明显矛盾的两句话应该被判定为冲突")
    }

    /// 只是补充信息，不算冲突
    func testNoConflictWhenComplementary() async throws {
        try XCTSkipUnless(LLMSettings.shared.isReady, "没配模型，跳过网络用例")
        let note = await LoreConflictChecker.check(
            content: "她怕水，七岁差点淹死",
            bio: "苏晚棠的梦想是成为漫画家，性格安静。"
        )
        XCTAssertNil(note, "补充设定不应被判定为冲突")
    }

    /// 真实调用：设定「毕业后从事心理专业」，应补出「工作/职业/心理」这类用户真的会说的词
    func testExpandWithRealModel() async throws {
        try XCTSkipUnless(LLMSettings.shared.isReady, "没配模型，跳过网络用例")
        let keys = await LoreKeywordExpander.expand(title: "心理咨询师", content: "毕业后从事心理专业")
        XCTAssertGreaterThanOrEqual(keys.count, 5)
        XCTAssertTrue(keys.contains { $0.contains("工作") || $0.contains("职业") || $0.contains("心理") },
                      "补出来的词没有一个能命中「你现在做什么工作」这类提问：\(keys)")
    }
}
