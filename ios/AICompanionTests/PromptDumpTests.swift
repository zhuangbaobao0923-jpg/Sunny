import XCTest
@testable import AICompanion

@MainActor
final class PromptDumpTests: XCTestCase {
    func testDumpPromptWithLore() {
        let entry = LoreEntry(characterID: "dump", title: "画画",
                              keys: ["画画"], content: "纳兰铮喜欢画画，画的是水墨山水。",
                              priority: 2)
        let character = Character(
            id: "dump", name: "纳兰铮", author: "@test", imageName: "char_nalanzheng",
            tags: [], bio: "纳兰铮，性子冷，爱财。", opening: "", replies: [],
            likeCount: 0, unread: 0, lastMessage: "", lastActivity: Date()
        )
        let prompt = PersonaPrompt.system(for: character, level: 1, memory: [],
                                          recalled: [], lore: [entry], timeLine: "【时间】测试")
        print("PROMPT_BEGIN")
        print(prompt)
        print("PROMPT_END")
        XCTAssertTrue(prompt.contains("【世界设定】"))
        XCTAssertTrue(prompt.contains("纳兰铮喜欢画画"))
    }
}
