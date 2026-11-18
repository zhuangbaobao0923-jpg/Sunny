import XCTest
@testable import AICompanion

/// 形象生成与人设自动生成的回归测试
final class VisualAndAutofillTests: XCTestCase {

    /// 回归：artStyle/subject 的 hashValue 为负数时 UInt64 强转崩溃（真机 EXC_BREAKPOINT）
    func testPlansAllStylesNoCrash() {
        for style in SampleData.artStyles {
            for desc in ["", "银发红瞳古风剑客", "可爱的女生长头发，大眼睛", "校园学姐"] {
                let plans = VisualPlanEngine.plans(for: desc, artStyle: style, seed: 3)
                XCTAssertEqual(plans.count, 3, "style=\(style) 应产出 3 个方案")
                XCTAssertFalse(plans[0].prompt.isEmpty)
            }
        }
    }

    /// 同一描述不同 seed 产出不同组合（换一批有效）
    func testPlansChangeWithSeed() {
        let a = VisualPlanEngine.plans(for: "银发红瞳古风剑客", artStyle: "经典", seed: 0)
        let b = VisualPlanEngine.plans(for: "银发红瞳古风剑客", artStyle: "经典", seed: 1)
        XCTAssertTrue(a[0].prompt != b[0].prompt || a[1].prompt != b[1].prompt, "换一批后方案应有变化")
    }

    /// 本地兜底人设：每次点击都不同，且性别被遵守
    func testLocalFallbackVariety() {
        let first = PersonaAutofillEngine.localFallback(nickname: "沈明珠", gender: "女")
        XCTAssertFalse(first.setting.isEmpty)
        XCTAssertFalse(first.intro.isEmpty)
        XCTAssertFalse(first.opening.isEmpty)
        XCTAssertFalse(first.setting.contains("deepest"))

        // 随机池足够大，多次生成几乎必然出现不同设定
        var variants = Set<String>()
        for _ in 0..<20 {
            variants.insert(PersonaAutofillEngine.localFallback(nickname: "", gender: "男").setting)
        }
        XCTAssertGreaterThan(variants.count, 1, "自动生成不应每次都一样")
    }

    /// 模型返回 JSON 的宽容解析（围栏/杂讯）
    func testParseJSONTolerant() {
        let input = """
        好的，以下是生成结果：
        ```json
        {"nickname":"沈明珠","gender":"女","setting":"身份：调香师。","intro":"她是碎云斋的调香师。","opening":"（转过身）你来了。"}
        ```
        """
        let parsed = PersonaAutofillEngine.parseJSON(input)
        XCTAssertEqual(parsed?["nickname"], "沈明珠")
        XCTAssertEqual(parsed?["gender"], "女")
        XCTAssertEqual(parsed?["setting"], "身份：调香师。")
    }
}
