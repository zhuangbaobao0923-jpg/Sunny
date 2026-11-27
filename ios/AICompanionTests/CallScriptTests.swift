import XCTest
@testable import AICompanion

/// 通话话术与「电话模式」提示词的回归测试。
/// 一通陪伴电话靠的就是这套台词：招呼 → 轻问 → 安慰 → 三个笑话 → 结束语，
/// 任何一环缺了，用户那边就是「TA 半天不说话」或者「说了两句就挂」。
final class CallScriptTests: XCTestCase {

    private func character(id: String, name: String, bio: String = "测试人设") -> Character {
        Character(
            id: id, name: name, author: "@test",
            imageName: "char_shenjinghan", tags: [], bio: bio,
            opening: "", replies: [], likeCount: 0, unread: 0,
            lastMessage: "", lastActivity: Date()
        )
    }

    /// 种子角色 + 自建角色 + 未知角色，三档都要有完整的电话话术
    private var samples: [Character] {
        [
            character(id: "sjh", name: "沈惊寒"),
            character(id: "nlz", name: "纳兰铮"),
            character(id: "swt", name: "苏晚棠"),
            character(id: "xwj", name: "谢无咎"),
            character(id: "lyc", name: "凌云裳"),
            character(id: "custom-xiao", name: "萧玄策"),
            character(id: "custom-pei", name: "裴经年"),
            character(id: "unknown", name: "路人甲")
        ]
    }

    func testGreetingIsPhoneReadyAndFillsNickname() {
        for c in samples {
            let line = CallScript.greeting(for: c, userName: "小鱼")
            XCTAssertFalse(line.isEmpty, "\(c.name) 没有招呼语")
            XCTAssertFalse(line.contains("{name}"), "\(c.name) 的招呼语占位符没替换")
        }
        // 昵称空着也不能念出「喂，，在吗」
        for c in samples {
            let line = CallScript.greeting(for: c, userName: "  ")
            XCTAssertFalse(line.contains("，，"), "\(c.name) 昵称缺失时句式塌了：\(line)")
        }
    }

    func testEveryCharacterHasCheckInChatterAndThreeJokes() {
        for c in samples {
            XCTAssertFalse(CallScript.checkIn(for: c, userName: "小鱼").isEmpty, "\(c.name) 缺冷场轻问")
            XCTAssertGreaterThanOrEqual(CallScript.chatter(for: c).count, 5, "\(c.name) 碎碎念太少")
            XCTAssertEqual(CallScript.jokes(for: c).count, 3, "\(c.name) 笑话必须是 3 个")
            XCTAssertGreaterThanOrEqual(CallScript.company(for: c).count, 4, "\(c.name) 陪伴话术太少")
        }
    }

    func testComfortStartsWithTheUnhappyCheck() {
        for c in samples {
            let comfort = CallScript.comfort(for: c)
            XCTAssertGreaterThanOrEqual(comfort.count, 4, "\(c.name) 安慰话术太少")
            XCTAssertTrue(comfort[0].contains("不开心"),
                          "\(c.name) 安慰第一步应该先问「是不是不开心」：\(comfort[0])")
        }
    }

    func testFarewellAlwaysEndsWithComeBackAnytime() {
        for c in samples {
            let farewell = CallScript.farewell(for: c)
            XCTAssertTrue(farewell.contains("随时打给我"),
                          "\(c.name) 结束语必须留一句「你可以随时打给我」：\(farewell)")
        }
    }

    /// 碎碎念也可能是带昵称的（「{name}，你那边安静得很」）——
    /// 念之前必须替换，否则会真的念出「花括号 name」。
    func testSpokenLinesNeverLeakNamePlaceholder() {
        for c in samples {
            let pool = CallScript.chatter(for: c)
                + CallScript.comfort(for: c)
                + CallScript.jokes(for: c)
                + CallScript.company(for: c)
                + CallScript.smallTalk
            for line in pool {
                let spoken = CallScript.speakable(line, userName: "小鱼")
                XCTAssertFalse(spoken.contains("{name}"), "念出来还带着占位符：\(spoken)")
                XCTAssertFalse(spoken.isEmpty)
            }
        }
    }

    /// 音频被来电 / 别的 App 抢走又接回来时，要先交代一句，不能接着碎碎念
    func testResumeLineIsPerCharacterAndClean() {
        for c in samples {
            let line = CallScript.resumeLine(for: c, userName: "小鱼")
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("{name}"))
        }
        let a = CallScript.resumeLine(for: character(id: "sjh", name: "沈惊寒"), userName: "小鱼")
        let b = CallScript.resumeLine(for: character(id: "swt", name: "苏晚棠"), userName: "小鱼")
        XCTAssertNotEqual(a, b, "不同角色被中断后应该有各自的说法")
    }

    func testCallPromptSpeaksLikeAPhoneCall() {
        let c = character(id: "sjh", name: "沈惊寒")
        let call = PersonaPrompt.system(for: c, level: 3, memory: [], context: .call)
        XCTAssertTrue(call.contains("正在打电话"))
        XCTAssertTrue(call.contains("绝对不要写括号"))
        XCTAssertTrue(call.contains("单句不超过 25 个字"))
        // 文字聊天那套「用括号写动作」的规则不能出现在电话模式里
        XCTAssertFalse(call.contains("可以在句首或句中用全角括号"))

        let chat = PersonaPrompt.system(for: c, level: 3, memory: [])
        XCTAssertTrue(chat.contains("全角括号"))
        XCTAssertFalse(chat.contains("正在打电话"))
    }

    func testCallTalkNeverReturnsStageDirections() {
        let c = character(id: "sjh", name: "沈惊寒")
        for text in ["嗯", "我今天有点难过", "你好", "晚安", "在吗？"] {
            let reply = CallTalk.reply(for: c, history: [], userText: text, level: 3)
            XCTAssertFalse(reply.isEmpty)
            XCTAssertFalse(reply.contains("（"), "电话里不该念出括号动作：\(reply)")
            XCTAssertLessThanOrEqual(reply.count, 40, "电话回复太长：\(reply)")
        }
    }
}
