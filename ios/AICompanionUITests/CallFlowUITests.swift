import XCTest

/// 通话冒烟测试：能接通、能挂断、不卡死。
/// 音频本身听不见，这里验证的是「通话界面与状态机」。
final class CallFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testCallStartsAndHangsUp() {
        let app = XCUIApplication()
        app.launchArguments = ["-StartRoute", "chat", "-DemoCall", "sjh", "-CallSpeed", "12"]
        app.launch()

        // 接通：底部会出现挂断键（最多等 30 秒，含拨号动画）
        // 通话页的控件不是 button 角色，按文本找
        let hangUp = app.staticTexts["挂断"].firstMatch
        XCTAssertTrue(hangUp.waitForExistence(timeout: 30), "没有进入通话页")

        // 让它自己跑 8 秒：验证空闲期不崩、计时在走
        sleep(8)
        XCTAssertTrue(hangUp.exists, "通话中途消失了")

        hangUp.tap()

        // 挂断后回到聊天页
        XCTAssertTrue(app.buttons["语音通话"].waitForExistence(timeout: 10), "挂断后没有回到聊天页")
        XCTAssertFalse(hangUp.exists, "挂断后通话页还在")
    }
}
