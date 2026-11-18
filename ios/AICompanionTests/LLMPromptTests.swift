import XCTest
@testable import AICompanion

/// 真实模型接入：人设提示词、上下文装配、配置校验
final class LLMPromptTests: XCTestCase {

    private func makeCharacter() -> Character {
        Character(
            id: "sjh", name: "沈惊寒", author: "@宁落",
            imageName: "char_shenjinghan",
            tags: ["言情", "霸道"],
            bio: "大晟七皇子，母妃早逝，习惯把所有情绪都收进眼底。",
            opening: "（烛火摇曳）你来了。",
            replies: ["看完就烧了。知道太多的人，通常走不远。"],
            likeCount: 11, unread: 0,
            lastMessage: "", lastActivity: Date()
        )
    }

    func testSystemPromptCarriesPersonaRulesAndLevel() {
        let prompt = PersonaPrompt.system(for: makeCharacter(), level: 3, memory: [])
        XCTAssertTrue(prompt.contains("沈惊寒"))
        XCTAssertTrue(prompt.contains("大晟七皇子"))              // 人设
        XCTAssertTrue(prompt.contains("看完就烧了"))               // 说话风格样例
        XCTAssertTrue(prompt.contains("第一人称"))                 // 不 OOC 的硬规则
        XCTAssertTrue(prompt.contains("不要自称 AI"))
        XCTAssertTrue(prompt.contains("Lv.3"))                     // 亲密度注入
        XCTAssertTrue(prompt.contains("已经亲近"))                 // Lv3 语气提示
    }

    func testSystemPromptIncludesMemoryWithTimePhrase() {
        let memory = [MemoryTurn(user: "我先去忙了", reply: "去吧。", date: Date().addingTimeInterval(-5 * 3600))]
        let prompt = PersonaPrompt.system(for: makeCharacter(), level: 2, memory: memory)
        XCTAssertTrue(prompt.contains("5 小时前"))
        XCTAssertTrue(prompt.contains("我先去忙了"))
    }

    func testMessagesStartWithSystemAndEndWithUser() {
        let history: [ChatMessage] = [
            .assistant("（烛火摇曳）你来了。"),
            .user("你好"),
            .assistant("嗯。"),
            .failure("网络开小差了")
        ]
        let messages = PersonaPrompt.messages(
            for: makeCharacter(), history: history, userText: "今天风大吗", level: 1, memory: []
        )
        XCTAssertEqual(messages.first?["role"], "system")
        XCTAssertEqual(messages.last?["role"], "user")
        XCTAssertEqual(messages.last?["content"], "今天风大吗")
        // 失败气泡不进上下文
        XCTAssertFalse(messages.contains { $0["content"] == "网络开小差了" })
        // 历史 3 条 + system + 本轮 user
        XCTAssertEqual(messages.count, 5)
    }

    func testConfigBuildsChatCompletionsURL() {
        let config = LLMConfig(baseURL: "https://open.bigmodel.cn/api/paas/v4/", model: "glm-4-flash", apiKey: "k")
        XCTAssertEqual(config.chatCompletionsURL?.absoluteString,
                       "https://open.bigmodel.cn/api/paas/v4/chat/completions")
        XCTAssertTrue(config.isUsable)
        XCTAssertFalse(LLMConfig(baseURL: "", model: "", apiKey: "").isUsable)
    }

    func testProviderPresetsAreOpenAICompatible() {
        for provider in LLMProvider.allCases where provider != .custom {
            XCTAssertFalse(provider.model.isEmpty, "\(provider.rawValue) 缺默认模型")
            if provider != .ollama {
                XCTAssertTrue(provider.baseURL.hasPrefix("https://"), "\(provider.rawValue) 地址应为 https")
                XCTAssertTrue(provider.needsKey)
            } else {
                XCTAssertFalse(provider.needsKey)                  // 本机模型不需要 Key
                XCTAssertTrue(provider.baseURL.hasPrefix("http://"))
            }
        }
    }
}
