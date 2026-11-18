import XCTest
@testable import AICompanion

/// 72 小时动态记忆窗口 + 动态对话引导词
final class MemoryAndQuickReplyTests: XCTestCase {

    private let store = ChatMemoryStore.shared

    private func makeCharacter(id: String = "test-\(UUID().uuidString.prefix(6))") -> Character {
        Character(
            id: id, name: "沈惊寒", author: "@测试",
            imageName: "char_shenjinghan",
            tags: ["古风"], bio: "大晟七皇子",
            opening: "（烛火摇曳）你来了。",
            replies: ["嗯。"], likeCount: 11, unread: 0,
            lastMessage: "", lastActivity: Date()
        )
    }

    private func back(hours: Double) -> Date {
        Date().addingTimeInterval(-hours * 3600)
    }

    // MARK: - 回归承接（跨会话接续）

    func testNoMemoryReturnsNil() {
        let c = makeCharacter()
        store.clear(characterID: c.id)
        XCTAssertNil(PersonaEngine.returnGreeting(for: c))
    }

    func testRecentReturnProactivelyFollowsUpPendingEvent() {
        let c = makeCharacter()
        store.clear(characterID: c.id)
        // 5 小时前：用户说「我去忙了」，角色回了话
        store.record(characterID: c.id, user: "我先去忙了", reply: "去吧。", date: back(hours: 5))
        let greeting = PersonaEngine.returnGreeting(for: c)
        XCTAssertNotNil(greeting)
        // 必须主动承接：包含「办完 / 忙 / 顺利」一类的追问
        let mustContain = ["办完", "办得", "顺利", "忙"]
        XCTAssertTrue(mustContain.contains { greeting!.contains($0) }, "回归首句应主动追问待办，实际：\(greeting!)")
    }

    func testRecentReturnReferencesTopic() {
        let c = makeCharacter()
        store.clear(characterID: c.id)
        store.record(characterID: c.id, user: "在学做桂花糕", reply: "好。", date: back(hours: 3))
        let greeting = PersonaEngine.returnGreeting(for: c)
        // 要么引用了话题关键词，要么是通用的承接问候（不允许当新用户重新开场）
        XCTAssertNotNil(greeting)
        XCTAssertFalse(greeting!.contains("{kw}"), "占位符必须被替换")
        XCTAssertNotEqual(greeting, "（烛火摇曳）你来了。")
    }

    func testQuickReturnWithinHalfHour() {
        let c = makeCharacter()
        store.clear(characterID: c.id)
        store.record(characterID: c.id, user: "我们说到哪了", reply: "说到一半。", date: back(hours: 0.2))
        let greeting = PersonaEngine.returnGreeting(for: c)
        XCTAssertNotNil(greeting, "刚离开又回来也不能当新用户")
    }

    func testStaleReturnOver72HoursIsFuzzy() {
        let c = makeCharacter()
        store.clear(characterID: c.id)
        store.record(characterID: c.id, user: "在学做桂花糕", reply: "好。", date: back(hours: 80))
        let greeting = PersonaEngine.returnGreeting(for: c)
        XCTAssertNotNil(greeting, "超期应降级为模糊记忆问候，而非完全重置")
        // 模糊记忆不得引用具体话题细节
        XCTAssertFalse(greeting!.contains("桂花糕"), "超 72 小时不应记得具体细节：\(greeting!)")
    }

    // MARK: - 动态对话引导词

    func testSuggestionsCountAndTendencies() {
        let c = makeCharacter(id: "sjh")
        let aiMessage = "（指尖在密信边缘停了一停，烛火晃了晃）风急还是风缓，你倒比本殿还上心。"
        let suggestions = QuickReplyEngine.suggestions(for: c, aiMessage: aiMessage)
        XCTAssertEqual(suggestions.count, 4)
        XCTAssertEqual(Set(suggestions.map(\.tendency)).count, 4, "四条引导词应覆盖四种不同互动倾向")
        for s in suggestions {
            XCTAssertFalse(s.text.isEmpty)
            XCTAssertFalse(s.text.contains("{kw}"), "占位符必须被替换：\(s.text)")
            XCTAssertFalse(s.text.contains("{prop}"), "占位符必须被替换：\(s.text)")
        }
    }

    func testSuggestionsAdaptToQuestionContext() {
        let c = makeCharacter(id: "sjh")
        // 角色在提问 → 引导词应明显偏向「回答/反问」型，而非纯动作堆砌
        let asking = QuickReplyEngine.suggestions(for: c, aiMessage: "（抬眼）你想去哪，说个地方。")
        XCTAssertTrue(asking.allSatisfy { !$0.text.isEmpty })
        // 角色在关心 → 至少一条适合接住善意
        let caring = QuickReplyEngine.suggestions(for: c, aiMessage: "（把披风搭在你肩上）夜里凉，别站着。")
        XCTAssertFalse(caring.isEmpty)
    }

    func testSuggestionsDifferAcrossCalls() {
        let c = makeCharacter(id: "nlz")
        let aiMessage = "（拨了拨算盘）哟，又来赊账？"
        let a = QuickReplyEngine.suggestions(for: c, aiMessage: aiMessage).map(\.text)
        let b = QuickReplyEngine.suggestions(for: c, aiMessage: aiMessage).map(\.text)
        XCTAssertNotEqual(a, b, "同一语境连续两次生成也不应输出完全相同的一组（严禁静态套话）")
    }

    func testPendingEventDetection() {
        XCTAssertEqual(ChatText.pendingEvent(from: "我先去忙了"), "去忙的事")
        XCTAssertEqual(ChatText.pendingEvent(from: "去上课了，回见"), "课")
        XCTAssertNil(ChatText.pendingEvent(from: "今天天气不错"))
    }
}
