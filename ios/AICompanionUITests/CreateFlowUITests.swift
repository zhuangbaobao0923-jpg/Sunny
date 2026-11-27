import XCTest

/// 创建角色 → 形象面板 → 返回 的回归测试。
/// 背景：用户反馈「保存形象后点退出，又回到形象面板」。
final class CreateFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchCreate() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-StartRoute", "create"]
        app.launch()
        return app
    }

    /// 打开面板 → 返回 → 再点创建页返回：不能又弹出面板
    func testBackDoesNotReopenStudio() {
        let app = launchCreate()

        let faceCard = app.buttons["create.faceCard"]
        XCTAssertTrue(faceCard.waitForExistence(timeout: 10), "创建页没有出现")

        faceCard.tap()
        let faceBack = app.buttons["face.back"]
        XCTAssertTrue(faceBack.waitForExistence(timeout: 8), "形象面板没有打开")

        faceBack.tap()
        XCTAssertTrue(faceCard.waitForExistence(timeout: 6), "返回后没有回到创建页")

        // 关键断言：再点创建页的返回，不能又把形象面板弹出来
        app.buttons["create.back"].tap()
        XCTAssertFalse(faceBack.waitForExistence(timeout: 1.5),
                       "点返回后又弹出了形象面板")
    }

    /// 真的生成一张、点「使用这张」，再退出：同样不能回到面板
    func testUseImageThenExitDoesNotReopenStudio() {
        let app = launchCreate()

        let faceCard = app.buttons["create.faceCard"]
        XCTAssertTrue(faceCard.waitForExistence(timeout: 10))
        faceCard.tap()

        let cta = app.buttons["face.cta"]
        XCTAssertTrue(cta.waitForExistence(timeout: 6))
        cta.tap()   // 生成图片

        // 等生成完成（最多 150 秒）：按钮变成「使用这张」
        let ready = expectation(description: "生成完成")
        let deadline = Date().addingTimeInterval(150)
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
            if cta.exists, cta.label.contains("使用这张") {
                timer.invalidate()
                ready.fulfill()
            } else if Date() > deadline {
                timer.invalidate()
            }
        }
        wait(for: [ready], timeout: 155)

        cta.tap()   // 使用这张 → 回到创建页
        print("TRACE_AFTER_USE_CARD: \(faceCard.exists) hittable=\(faceCard.isHittable)")
        XCTAssertTrue(faceCard.waitForExistence(timeout: 8), "选完图没有回到创建页")
        print("TRACE_BACK_FRAME_AFTER_SAVE: \(app.buttons["create.back"].frame)")
        app.buttons["create.back"].tap()
        XCTAssertFalse(app.buttons["face.back"].waitForExistence(timeout: 1.5),
                       "选完图再退出，又弹出了形象面板")
    }
}
