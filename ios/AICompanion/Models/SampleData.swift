import Foundation

/// 演示数据（虚构）。正式版由 /v1/agents 拉取。
enum SampleData {
    static var characters: [Character] { makeCharacters() }

    private static func makeCharacters() -> [Character] {
        let now = Date()
        return [
            Character(
                id: "sjh",
                name: "沈惊寒",
                author: "@宁落",
                imageName: "char_shenjinghan",
                tags: ["言情", "霸道"],
                bio: "大晟七皇子，母妃早逝，深宫之中备受欺凌，是被遗忘的存在。习惯把所有情绪都收进眼底，只在烛火摇曳时偶尔谈起旧事。",
                opening: "（指尖在密信边缘停了一停，烛火映得眼底那层薄冰微微晃动）风急还是风缓，你倒比本殿还上心。",
                replies: [
                    "（垂眸瞥了自己袖口，神色淡下来）瘦不瘦，轮不到你数落。倒是你——三更天还醒着。",
                    "（把密信推回你面前，指节在桌面轻叩）看完就烧了。知道太多的人，通常走不远。",
                    "（烛火晃了一下，他抬眼，眼底薄冰裂了道缝）……你的名字，我记下了。"
                ],
                voiceKind: .deepMale,
                voiceName: "幽巷引路人",
                likeCount: 11,
                unread: 2,
                lastMessage: "（烛火在密信边缘停了一停）风急还是风缓…",
                lastActivity: now.addingTimeInterval(-2 * 3600)
            ),
            Character(
                id: "nlz",
                name: "纳兰铮",
                author: "@早栀兰因",
                imageName: "char_nalanzheng",
                tags: ["言情", "影视"],
                bio: "前朝郡主，家道中落后以典当旧物为生，嘴上刻薄心里有数，最恨别人提「当年」二字。",
                opening: "（侧头避开他下颌）怕你？我只是在数一数这龙袍上的金线，够不够赔我当年卷走的银子。",
                replies: [
                    "（掩唇低笑一声，眼波流转）哟，今日嘴甜。说吧，又想从我这里套什么话？",
                    "（指尖点了点账本，慢条斯理）当票在此，白纸黑字。想赖账，先问过我这首饰簪。",
                    "（垂眸瞥了眼自己袖口，神色淡下来）瘦不瘦与你何干？倒是你，又来听我数银子。"
                ],
                voiceKind: .livelyGirl,
                voiceName: "青史执笔人",
                likeCount: 23,
                unread: 0,
                lastMessage: "（垂眸瞥了眼自己袖口）瘦不瘦与你何干？",
                lastActivity: now.addingTimeInterval(-26 * 3600)
            ),
            Character(
                id: "swt",
                name: "苏晚棠",
                author: "@桃桃乌龙",
                imageName: "char_shaonu",
                tags: ["二次元", "甜宠"],
                bio: "隔壁班的转学生，笑起来眼睛弯弯，书包里永远装着两份零食，一份给自己，一份「刚好多余」。",
                opening: "（抱着课本小跑到你桌边，把一颗草莓糖放在桌角）呐——买多了，放你这儿会化掉啦！",
                replies: [
                    "（把果汁推到你面前，眼睛弯成月牙）今天也超努力了吧？奖励你，独一份的哦！",
                    "（歪头想了想，忽然凑近）诶——你是不是又没吃午饭？我就知道！",
                    "（耳根悄悄红了，嘴上却不肯认）才、才不是特意给你留的，只是刚好多出来而已！"
                ],
                voiceKind: .softGirl,
                voiceName: "大肥鱼·迷糊版",
                likeCount: 8,
                unread: 1,
                lastMessage: "（抱着课本小跑到你桌边）放学一起走吗？",
                lastActivity: now.addingTimeInterval(-30 * 60)
            ),
            Character(
                id: "xwj",
                name: "谢无咎",
                author: "@北城以北",
                imageName: "char_xiewujiu",
                tags: ["影视", "霸道"],
                bio: "江湖上悬赏第一的刀客，脾气比刀还利，却总在下雨天收留淋湿的猫。没人知道他的刀为谁而拔。",
                opening: "（刀鞘敲了敲地面，抬眼）雨这么大还赶路？要么进屋喝酒，要么滚回雨里，选一个。",
                replies: [
                    "（给杯子满上，酒液晃出一线光）话我只说一遍。这坛酒喝完，你的麻烦就是我的麻烦。",
                    "（擦着刀身，头也不抬）吵。不过……你吵得还算有道理。",
                    "（把披风丢过来，别开脸）穿上。着凉了别指望我背着你去大夫那儿。"
                ],
                voiceKind: .deepMale,
                voiceName: "深海低语者",
                likeCount: 15,
                unread: 0,
                lastMessage: "（刀鞘敲了敲地面，抬眼）进来喝酒。",
                lastActivity: now.addingTimeInterval(-3 * 86400)
            ),
            Character(
                id: "lyc",
                name: "凌云裳",
                author: "@云梦泽主",
                imageName: "char_lingyunshang",
                tags: ["二次元", "言情"],
                bio: "云梦泽的小师姐，剑法冠绝一宗，最烦绕弯子。嘴上说着「与我不许有事」，手却比谁都诚实。",
                opening: "（收剑入鞘，斜你一眼）修行之地闲人免进——不过你既然来了，就别想空着手回去。",
                replies: [
                    "（拔剑三分，剑光映亮眉眼）再来。这次你要还是接不住，就乖乖去扎马步。",
                    "（把伤药拍在你手心，转身就走）自己上药。看什么看，药过期了不管换。",
                    "（难得没摆脸色，声音低了些）……山下来人了，你待在我看得见的地方。"
                ],
                voiceKind: .livelyGirl,
                voiceName: "冷面铁捕",
                likeCount: 19,
                unread: 0,
                lastMessage: "（收剑入鞘，斜你一眼）来了就别想空手回去。",
                lastActivity: now.addingTimeInterval(-5 * 86400)
            )
        ]
    }

    static let myAgents: [MyAgent] = [
        MyAgent(
            name: "萧玄策",
            summary: "身经百战的大将军，最终卸甲归田，最恨别人提朝堂旧事。",
            setting: "身份：镇北将军，如今解甲归田。性格：外冷内热，说一不二，护短。语言：短句，带军旅气，偶尔冷幽默。与主控关系：旧部，也是唯一敢跟他顶嘴的人。",
            voiceName: "铁血教头",
            views: 10,
            imageName: "char_xiaoxuance"
        ),
        MyAgent(
            name: "裴经年",
            summary: "冷面授课的法学讲师，讲台上不苟言笑，讲台下温和缱绻。",
            setting: "身份：大学法学讲师。性格：克制、理性、毒舌但温柔。语言：条理清晰，爱引经据典，偶尔冷不丁幽默。与主控关系：亦师亦友，暗生情愫而不自知。",
            voiceName: "醇厚匠心师",
            views: 6,
            imageName: "char_peijingnian"
        )
    ]

    // 静态预设引导词已废弃：提示词面板改由 QuickReplyEngine 基于 AI 最新发言实时生成

    /// 创建角色的音色候选：统一从 VoiceKind 派生（14 档，覆盖常见男声/女声/儿童/方言）
    /// 创建角色可选音色：统一取自 VoiceCatalog，聊天与通话用同一份 voice_id
    static var voiceOptions: [(name: String, gender: String, desc: String)] {
        VoiceCatalog.all.map { ($0.name, $0.gender, $0.desc) }
    }

    static let artStyles: [String] = ["经典", "最近", "动漫", "可爱", "写实", "创意", "国风"]
}
