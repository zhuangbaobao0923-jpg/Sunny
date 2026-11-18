import XCTest
@testable import AICompanion

/// 聊天输入框回归测试
@MainActor
final class ChatInputTests: XCTestCase {

    /// 发送后模型里的输入必须立刻清空（View 层的 TextField 回写问题由 ChatView 兜底）
    func testSendClearsInput() {
        let model = ChatModel(character: SampleData.characters[0],
                              service: MockChatService(failureRate: 0))
        model.input = "hello"
        model.send()
        XCTAssertTrue(model.input.isEmpty, "发送后 input 必须为空，否则输入框会残留上一条")
        model.cancel()
    }

    /// 空输入不能发出去，也不能把内容吃掉
    func testEmptyInputDoesNotSend() {
        let model = ChatModel(character: SampleData.characters[0],
                              service: MockChatService(failureRate: 0))
        let before = model.messages.count
        model.input = "   "
        model.send()
        XCTAssertEqual(model.messages.count, before)
        XCTAssertEqual(model.input, "   ")
    }
}
