import XCTest
@testable import AICompanion

final class LoreTests: XCTestCase {
    private let characterID = "test-lore"

    override func tearDown() {
        LoreStore.shared.clear(characterID: characterID)
        super.tearDown()
    }

    private func seed() {
        LoreStore.shared.upsert(LoreEntry(characterID: characterID, title: "师门",
                                          keys: ["昆仑", "师门"],
                                          content: "师门在昆仑山，门规不许下山惹事。",
                                          priority: 2))
        LoreStore.shared.upsert(LoreEntry(characterID: characterID, title: "剑",
                                          keys: ["佩剑"],
                                          content: "她的佩剑叫霜寒，是师父传的。",
                                          priority: 1))
    }

    /// 提到关键词才注入
    func testRetrieveOnKeyword() {
        seed()
        let hit = LoreRetriever.retrieve(input: "你师门在昆仑山吗", characterID: characterID)
        XCTAssertEqual(hit.count, 1)
        XCTAssertTrue(hit[0].content.contains("昆仑山"))
    }

    /// 核心设定常驻：没命中关键词也会被带上（这是「核心」对用户的承诺）
    func testCoreEntryIsAlwaysInjected() {
        seed()
        let list = LoreRetriever.retrieve(input: "今天吃什么", characterID: characterID)
        XCTAssertEqual(list.count, 1)
        XCTAssertTrue(list[0].content.contains("昆仑山"))
    }

    /// 普通设定不命中就不注入，不占 token
    func testNormalEntryNotInjectedWithoutKeyword() {
        LoreStore.shared.upsert(LoreEntry(characterID: characterID, title: "佩剑",
                                          keys: ["佩剑"], content: "她的佩剑叫霜寒",
                                          priority: 0))
        let list = LoreRetriever.retrieve(input: "今天吃什么", characterID: characterID)
        XCTAssertTrue(list.allSatisfy { !$0.content.contains("霜寒") })
    }

    /// 停用的条目不参与注入
    func testDisabledEntryIgnored() {
        var entry = LoreEntry(characterID: characterID, title: "旧设定",
                              keys: ["昆仑"], content: "旧版本设定", priority: 2)
        entry.enabled = false
        LoreStore.shared.upsert(entry)
        XCTAssertTrue(LoreRetriever.retrieve(input: "昆仑", characterID: characterID).isEmpty)
    }

    /// 最多 3 条，且核心设定优先
    func testLimitAndPriority() {
        for index in 0..<5 {
            LoreStore.shared.upsert(LoreEntry(characterID: characterID, title: "条目\(index)",
                                              keys: ["昆仑"], content: "设定\(index)",
                                              priority: index == 4 ? 2 : 0))
        }
        let list = LoreRetriever.retrieve(input: "昆仑", characterID: characterID)
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list.first?.content, "设定4")
    }

    /// 标题也算命中词：用户往往直接说标题里的说法
    func testTitleCountsAsKeyword() {
        LoreStore.shared.upsert(LoreEntry(characterID: characterID, title: "心理咨询师",
                                          keys: ["心理"], content: "毕业后从事心理专业",
                                          priority: 1))
        let hit = LoreRetriever.retrieve(input: "心理咨询师难考吗", characterID: characterID)
        XCTAssertEqual(hit.count, 1)
    }

    /// 「你喜欢画画」要改写成第三人称，否则模型会把「你」理解成用户
    func testThirdPersonRewrite() {
        XCTAssertEqual(LoreEditSheet.thirdPerson("你喜欢画画", name: "纳兰铮"), "纳兰铮喜欢画画")
        XCTAssertEqual(LoreEditSheet.thirdPerson("她喜欢画画", name: "纳兰铮"), "她喜欢画画")
        XCTAssertEqual(LoreEditSheet.thirdPerson("你喜欢画画", name: ""), "你喜欢画画")
    }

    /// 提示词里真的带上了世界设定
    func testPromptInjectsLore() {
        seed()
        let character = Character(
            id: characterID, name: "测试角色", author: "@test", imageName: "char_xiewujiu",
            tags: [], bio: "测试", opening: "", replies: [], likeCount: 0,
            unread: 0, lastMessage: "", lastActivity: Date()
        )
        let messages = PersonaPrompt.messages(for: character, history: [],
                                              userText: "你师门在哪", level: 1, memory: [])
        let system = messages.first?["content"] ?? ""
        XCTAssertTrue(system.contains("【世界设定】"))
        XCTAssertTrue(system.contains("昆仑山"))
    }
}
