import XCTest
@testable import AICompanion

final class MemoryTests: XCTestCase {
    private let characterID = "test-memory"

    override func tearDown() {
        MemoryStore.shared.clear(characterID: characterID)
        super.tearDown()
    }

    /// 规则抽取：能从句子里抽出「用户养了猫」这种条目
    func testExtractCatFact() {
        let entries = MemoryExtractor.candidates(from: "我养了一只猫，叫团子，特别黏人")
        XCTAssertFalse(entries.isEmpty)
        let first = entries[0]
        XCTAssertTrue(first.content.hasPrefix("用户"))
        XCTAssertTrue(first.keys.contains("猫") || first.keys.contains("团子"))
    }

    /// 问句不记：「你养猫了吗」不是事实
    func testQuestionIsNotMemory() {
        let entries = MemoryExtractor.candidates(from: "你养猫了吗")
        XCTAssertTrue(entries.isEmpty)
    }

    /// 检索：提到命中词才带出记忆，没提到就一条都不占
    func testRetrieveOnlyWhenMentioned() {
        MemoryStore.shared.upsert(MemoryEntry(characterID: characterID,
                                              keys: ["猫", "团子"],
                                              content: "用户养了一只猫，叫团子"))
        let hit = MemoryRetriever.retrieve(input: "团子今天又抓沙发了", characterID: characterID)
        XCTAssertEqual(hit.count, 1)

        let miss = MemoryRetriever.retrieve(input: "今天加班到十点", characterID: characterID)
        XCTAssertTrue(miss.isEmpty)
    }

    /// 模型返回的 JSON 能解析，哪怕套了代码块或前后带解释
    func testParseModelJSON() {
        let raw = """
        好的，结果如下：
        ```json
        [{"content":"用户养了一只猫，叫团子","keys":["猫","团子"]}]
        ```
        """
        let entries = MemoryDescriber.parse(raw)
        XCTAssertEqual(entries?.count, 1)
        XCTAssertEqual(entries?.first?.keys.contains("团子"), true)
    }

    /// 模型说「没什么值得记的」→ 空数组，不要当成失败
    func testParseEmptyArray() {
        XCTAssertEqual(MemoryDescriber.parse("[]")?.count, 0)
    }

    /// 完全不是 JSON → 解析失败，交由规则兜底
    func testParseGarbageReturnsNil() {
        XCTAssertNil(MemoryDescriber.parse("我觉得这句话不用记"))
    }

    /// 时间锚：包含日期、时段和「认识第几天」
    func testTimeAnchor() {
        ChatMemoryStore.shared.markFirstSeen(characterID: characterID,
                                             date: Date().addingTimeInterval(-4 * 86400))
        let line = TimeAnchor.line(for: characterID)
        XCTAssertTrue(line.contains("【时间】"))
        XCTAssertTrue(line.contains("认识第"))
    }

    /// 提示词里真的带上了时间和检索到的记忆
    func testPromptCarriesTimeAndMemory() {
        // 用测试专用 id：别碰真实的 sjh，单测和 App 共用同一个沙盒
        MemoryStore.shared.upsert(MemoryEntry(characterID: "test-prompt",
                                              keys: ["猫", "团子"],
                                              content: "用户养了一只猫，叫团子"))
        let character = Character(
            id: "test-prompt", name: "测试角色", author: "@test", imageName: "char_shenjinghan",
            tags: [], bio: "测试", opening: "", replies: [], likeCount: 0,
            unread: 0, lastMessage: "", lastActivity: Date()
        )
        let messages = PersonaPrompt.messages(for: character, history: [], userText: "团子今天很乖",
                                              level: 1, memory: [])
        let system = messages.first?["content"] ?? ""
        XCTAssertTrue(system.contains("【时间】"))
        XCTAssertTrue(system.contains("团子"))
        MemoryStore.shared.clear(characterID: "test-prompt")
    }
}
