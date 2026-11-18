import Foundation

struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    let text: String
    let isUser: Bool
    let time: Date

    init(id: UUID = UUID(), text: String, isUser: Bool, time: Date = Date()) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.time = time
    }
}

struct RoleCharacter: Identifiable, Hashable {
    let id: UUID
    var name: String
    var title: String
    var persona: MBTIType
    var tagline: String
    var intimacy: Int
    var unread: Int
    var paletteIndex: Int
    var isUserCreated: Bool

    init(
        id: UUID = UUID(),
        name: String,
        title: String,
        persona: MBTIType,
        tagline: String,
        intimacy: Int = 1,
        unread: Int = 0,
        paletteIndex: Int = 0,
        isUserCreated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.persona = persona
        self.tagline = tagline
        self.intimacy = intimacy
        self.unread = unread
        self.paletteIndex = paletteIndex
        self.isUserCreated = isUserCreated
    }

    var intimacyLabel: String {
        switch intimacy {
        case 0: return "初识"
        case 1: return "陌生"
        case 2: return "熟悉"
        case 3: return "亲近"
        case 4: return "挚友"
        default: return "CP"
        }
    }

    var initial: String {
        String(name.prefix(1))
    }
}

extension RoleCharacter {
    static let samples: [RoleCharacter] = [
        RoleCharacter(
            name: "顾言",
            title: "INTJ 军师",
            persona: .intj,
            tagline: "说话直接，记得你所有细节",
            intimacy: 3,
            unread: 2,
            paletteIndex: 0
        ),
        RoleCharacter(
            name: "温野",
            title: "INFP 深夜电台",
            persona: .infp,
            tagline: "不评判，只陪你把话说完",
            intimacy: 2,
            unread: 1,
            paletteIndex: 1
        ),
        RoleCharacter(
            name: "裴经年",
            title: "ENFJ 生活管家",
            persona: .enfj,
            tagline: "会盯着你吃饭睡觉的那种",
            intimacy: 2,
            unread: 0,
            paletteIndex: 2
        ),
        RoleCharacter(
            name: "阿岚",
            title: "ENTP 辩论搭子",
            persona: .entp,
            tagline: "先反驳你，再帮你想得更远",
            intimacy: 1,
            unread: 0,
            paletteIndex: 3
        ),
        RoleCharacter(
            name: "苏慢",
            title: "ISFP 生活记录者",
            persona: .isfp,
            tagline: "把普通的一天说出光来",
            intimacy: 1,
            unread: 0,
            paletteIndex: 4
        ),
        RoleCharacter(
            name: "程野",
            title: "ESTP 行动派",
            persona: .estp,
            tagline: "别想了，先做一步再说",
            intimacy: 1,
            unread: 0,
            paletteIndex: 5
        )
    ]
}
