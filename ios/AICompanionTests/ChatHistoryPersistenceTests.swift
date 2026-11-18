import XCTest
@testable import AICompanion

/// 聊天记录 / 亲密度等级本地持久化：退出 App 再进来必须原样恢复
@MainActor
final class ChatHistoryPersistenceTests: XCTestCase {

    private func makeCharacter(id: String = "persist-\(UUID().uuidString.prefix(6))") -> Character {
        Character(
            id: id, name: "沈惊寒", author: "@测试",
            imageName: "char_shenjinghan",
            tags: ["古风"], bio: "大晟七皇子",
            opening: "（烛火摇曳）你来了。",
            replies: ["嗯。"], likeCount: 11, unread: 0,
            lastMessage: "", lastActivity: Date()
        )
    }

    private func clean(_ id: String) {
        UserDefaults.standard.removeObject(forKey: "chat.history.\(id)")
    }

    func testSnapshotRoundTripKeepsMessagesAndLevel() {
        let id = "rt-\(UUID().uuidString.prefix(6))"
        let messages = [
            ChatMessage.assistant("开场白"),
            ChatMessage.user("你好"),
            ChatMessage.assistant("（抬眼）来了。"),
            ChatMessage.failure("失败气泡不落盘")
        ]
        let snapshot = ChatHistoryStorage.snapshot(messages: messages, rounds: 47, likeCount: 12, liked: true)
        ChatHistoryStorage.save(snapshot, characterID: id)
        defer { clean(id) }

        let restored = ChatHistoryStorage.load(characterID: id)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.messages.count, 3)                     // 失败气泡被过滤
        XCTAssertEqual(restored?.messages[1].role, "user")
        XCTAssertEqual(restored?.messages[1].text, "你好")
        XCTAssertEqual(restored?.rounds, 47)                            // 47 回合 = Lv.3
        XCTAssertEqual(restored?.likeCount, 12)
        XCTAssertTrue(restored?.liked ?? false)
    }

    func testChatModelRestoresHistoryAndLevel() {
        let c = makeCharacter()
        clean(c.id)
        defer { clean(c.id) }

        // 先保存一份历史：3 回合 + 一条用户消息
        let history = ChatHistoryStorage.snapshot(
            messages: [.assistant("上次的话"), .user("在吗"), .assistant("（把字条拿近了又看了一遍）嗯。")],
            rounds: 41, likeCount: 15, liked: true
        )
        ChatHistoryStorage.save(history, characterID: c.id)

        // 新建 ChatModel：应当恢复记录而不是重新开场白
        let model = ChatModel(character: c, service: MockChatService(failureRate: 0))
        XCTAssertEqual(model.messages.count, 3)
        XCTAssertEqual(model.messages.first?.text, "上次的话")           // 不再是开场白
        XCTAssertEqual(model.intimacy.level, 3)                          // 41 回合 → Lv.3
        XCTAssertEqual(model.likeCount, 15)
        XCTAssertTrue(model.liked)

        // 再聊一轮 → 落盘后回合数 +1（极速 Mock：首字 10ms、逐字 1ms）
        let fast = MockChatService(firstTokenDelay: .milliseconds(10), chunkInterval: .milliseconds(1))
        let model2 = ChatModel(character: c, service: fast)
        XCTAssertEqual(model2.messages.count, 3)
        model2.input = "测试"
        model2.send()
        let exp = expectation(description: "stream")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exp.fulfill() }
        wait(for: [exp], timeout: 3)
        let saved = ChatHistoryStorage.load(characterID: c.id)
        XCTAssertEqual(saved?.rounds, 42)
        XCTAssertEqual(saved?.messages.last?.role, "assistant")
    }

    func testEmptyHistoryFallsBackToOpening() {
        let c = makeCharacter()
        clean(c.id)
        defer { clean(c.id) }
        let model = ChatModel(character: c, service: MockChatService(failureRate: 0))
        XCTAssertFalse(model.messages.isEmpty)
        // 无历史 → 开场白或 72h 承接问候，总之不是崩溃/空屏
        XCTAssertTrue(model.messages.allSatisfy { !$0.text.isEmpty })
    }
}
