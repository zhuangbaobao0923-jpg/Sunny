import XCTest
@testable import AICompanion

final class IntimacyProgressTests: XCTestCase {
    func testInitialState() {
        let progress = IntimacyProgress()
        XCTAssertEqual(progress.level, 1)
        XCTAssertEqual(progress.roundsIntoLevel, 0)
        XCTAssertEqual(progress.progress, 0, accuracy: 0.0001)
        XCTAssertFalse(progress.voiceUnlocked)
    }

    func testLevelUpAfterTwentyRounds() {
        var progress = IntimacyProgress(rounds: 19)
        XCTAssertEqual(progress.level, 1)
        XCTAssertTrue(progress.recordTurn())
        XCTAssertEqual(progress.level, 2)
        XCTAssertEqual(progress.roundsIntoLevel, 0)
    }

    func testMiddleOfLevel() {
        let progress = IntimacyProgress(rounds: 23)
        XCTAssertEqual(progress.level, 2)
        XCTAssertEqual(progress.roundsIntoLevel, 3)
        XCTAssertEqual(progress.counterText, "(3/20)")
        XCTAssertEqual(progress.progress, 0.15, accuracy: 0.0001)
    }

    func testCapsAtLevelFive() {
        var progress = IntimacyProgress(rounds: 80)
        XCTAssertEqual(progress.level, 5)
        XCTAssertTrue(progress.voiceUnlocked)
        XCTAssertEqual(progress.progress, 1, accuracy: 0.0001)
        // 满级后不再升级、不再累计
        XCTAssertFalse(progress.recordTurn())
        XCTAssertEqual(progress.level, 5)
        XCTAssertEqual(progress.rounds, 80)
    }

    func testNegativeRoundsClamped() {
        XCTAssertEqual(IntimacyProgress(rounds: -10).rounds, 0)
    }
}

final class TimeLabelTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testTodayShowsClockOnly() {
        let now = date(2026, 11, 1, 20, 0)
        let target = date(2026, 11, 1, 14, 32)
        XCTAssertEqual(TimeLabel.listLabel(target, now: now, calendar: calendar), "14:32")
    }

    func testYesterdayPrefix() {
        let now = date(2026, 11, 1, 9, 0)
        let target = date(2026, 10, 31, 23, 5)
        XCTAssertEqual(TimeLabel.listLabel(target, now: now, calendar: calendar), "昨天 23:05")
    }

    func testOlderShowsMonthDay() {
        let now = date(2026, 11, 1, 9, 0)
        let target = date(2026, 8, 14, 8, 0)
        XCTAssertEqual(TimeLabel.listLabel(target, now: now, calendar: calendar), "8/14")
    }

    func testClockIsZeroPadded() {
        XCTAssertEqual(TimeLabel.clock(date(2026, 11, 1, 9, 5), calendar: calendar), "09:05")
    }
}

final class AgentDraftTests: XCTestCase {
    func testEmptyDraftCannotSubmit() {
        let draft = AgentDraft()
        XCTAssertFalse(draft.canSubmit)
        XCTAssertEqual(draft.missingFields.count, 6) // 昵称/性别/设定/简介/开场白/音色
    }

    func testCompleteDraftCanSubmit() {
        var draft = AgentDraft()
        draft.nickname = "沈砚舟"
        draft.gender = "男"
        draft.setting = "设定"
        draft.intro = "简介"
        draft.opening = "开场"
        draft.voice = "清冷少年"
        XCTAssertTrue(draft.canSubmit)
        XCTAssertTrue(draft.missingFields.isEmpty)
    }

    func testWhitespaceOnlyNicknameIsInvalid() {
        var draft = AgentDraft()
        draft.nickname = "   "
        XCTAssertTrue(draft.missingFields.contains("昵称"))
    }
}
