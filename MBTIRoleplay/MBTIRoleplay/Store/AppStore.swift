import SwiftUI
import Observation

@MainActor
@Observable
final class AppStore {
    var myType: MBTIType = .infp
    var characters: [RoleCharacter] = RoleCharacter.samples
    var conversations: [UUID: [ChatMessage]] = [:]
    var typing: Set<UUID> = []

    init() {
        seedConversations()
    }

    private func seedConversations() {
        guard characters.count >= 4 else { return }
        let now = Date()

        conversations[characters[0].id] = [
            ChatMessage(
                text: "你昨晚没睡。不用解释，你的回复间隔和错别字频率暴露了。说吧，又想到什么新点子卡住了？",
                isUser: false,
                time: now.addingTimeInterval(-5400)
            ),
            ChatMessage(
                text: "……你怎么连这个都记",
                isUser: true,
                time: now.addingTimeInterval(-5300)
            ),
            ChatMessage(
                text: "我记一切对我重要的东西。你算一个。——行了，先说你那个点子，我列了三个风险，听完再睡。",
                isUser: false,
                time: now.addingTimeInterval(-5200)
            )
        ]

        conversations[characters[1].id] = [
            ChatMessage(
                text: "今天也没什么事，就是有点空。",
                isUser: true,
                time: now.addingTimeInterval(-10800)
            ),
            ChatMessage(
                text: "嗯……空也是一种感觉，不用急着把它填满。要不要说说，是什么时候开始的？",
                isUser: false,
                time: now.addingTimeInterval(-10700)
            )
        ]

        conversations[characters[2].id] = [
            ChatMessage(
                text: "提醒你一下，今天的午饭时间已经过了二十分钟。",
                isUser: false,
                time: now.addingTimeInterval(-18000)
            )
        ]

        conversations[characters[3].id] = []
        conversations[characters[4].id] = []
        conversations[characters[5].id] = []
    }

    func messages(for characterID: UUID) -> [ChatMessage] {
        conversations[characterID] ?? []
    }

    func lastMessage(for characterID: UUID) -> ChatMessage? {
        conversations[characterID]?.last
    }

    var unreadTotal: Int {
        characters.reduce(0) { $0 + $1.unread }
    }

    func markRead(_ characterID: UUID) {
        guard let index = characters.firstIndex(where: { $0.id == characterID }) else { return }
        if characters[index].unread != 0 {
            characters[index].unread = 0
        }
    }

    func send(_ text: String, to character: RoleCharacter) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var list = conversations[character.id] ?? []
        list.append(ChatMessage(text: trimmed, isUser: true, time: Date()))
        conversations[character.id] = list

        typing.insert(character.id)

        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            let reply = replyText(for: character, userSaid: trimmed, messageCount: list.count)
            var current = conversations[character.id] ?? []
            current.append(ChatMessage(text: reply, isUser: false, time: Date()))
            conversations[character.id] = current
            typing.remove(character.id)
            growIntimacy(character.id, messageCount: current.count)
        }
    }

    private func growIntimacy(_ characterID: UUID, messageCount: Int) {
        guard let index = characters.firstIndex(where: { $0.id == characterID }) else { return }
        let target = min(5, messageCount / 4)
        if target > characters[index].intimacy {
            characters[index].intimacy = target
        }
    }

    private func replyText(for character: RoleCharacter, userSaid: String, messageCount: Int) -> String {
        let pool = PersonaVoice.lines(for: character.persona)
        let base = pool[messageCount % pool.count]

        if userSaid.contains("?") || userSaid.contains("？") {
            return base
        }
        if userSaid.count <= 4 {
            return base + " 就这些？"
        }
        return base
    }

    var complementaryRoles: [RoleCharacter] {
        let mine = Array(myType.code)
        return characters
            .filter { role in
                let theirs = Array(role.persona.code)
                let diff = zip(mine, theirs).filter { $0 != $1 }.count
                return diff >= 3
            }
            .sorted { $0.intimacy > $1.intimacy }
    }

    var sameTypeRoles: [RoleCharacter] {
        let mine = Array(myType.code)
        return characters.filter { role in
            let theirs = Array(role.persona.code)
            let same = zip(mine, theirs).filter { $0 == $1 }.count
            return same >= 3
        }
    }

    func addCharacter(name: String, title: String, persona: MBTIType, tagline: String) {
        let role = RoleCharacter(
            name: name,
            title: title,
            persona: persona,
            tagline: tagline,
            intimacy: 0,
            unread: 0,
            paletteIndex: characters.count,
            isUserCreated: true
        )
        characters.insert(role, at: 0)
        conversations[role.id] = []
    }
}
