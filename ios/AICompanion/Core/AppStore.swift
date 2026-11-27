import Observation
import SwiftUI

enum AppTab: Hashable {
    case rec
    case create
    case mine
}

enum Route: Hashable {
    case msgs
    case agents          // 高光时刻 · 全部角色
    case chat(String)
    case settings
    case profile
    case voice
    case model
    case memory
    case lore
    case loreCharacter(String)
}

@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .rec
    var recPath: [Route] = []
    var minePath: [Route] = []

    /// 底部导航只在 Root 页显示（Task 页隐藏）
    var showsTabBar: Bool {
        switch tab {
        case .rec: return recPath.isEmpty
        case .mine: return minePath.isEmpty
        case .create: return false
        }
    }

    func push(_ route: Route) {
        switch tab {
        case .mine: minePath.append(route)
        case .rec, .create: recPath.append(route)
        }
    }

    func popToRoot() {
        switch tab {
        case .mine: minePath.removeAll()
        case .rec, .create: recPath.removeAll()
        }
    }
}

@MainActor
@Observable
final class AppStore {
    var characters: [Character]
    var myAgents: [MyAgent]
    /// 云端别人发布的角色（登录后拉取，进首页推荐池）
    var cloudCharacters: [Character] = []
    var profile: UserProfile
    var toast: String?

    private let chatService: ChatService?
    private var toastTask: Task<Void, Never>?

    init(
        characters: [Character] = SampleData.characters,
        myAgents: [MyAgent] = SampleData.myAgents,
        profile: UserProfile = ProfileStorage.load(),
        chatService: ChatService? = nil
    ) {
        self.characters = characters
        self.myAgents = myAgents
        self.profile = profile
        self.chatService = chatService
        restoreLastActivity()
    }

    /// 模型未配置 / 未启用时自动回落到本地人设引擎，保证任何时候都能聊
    private var activeService: ChatService {
        if let chatService { return chatService }
        let llm = LLMSettings.shared
        return llm.isReady ? RemoteChatService(config: llm.config) : MockChatService(failureRate: 0)
    }

    /// 启动时用本地聊天快照回填首页/热聊列表的「最后一条消息」，和聊天页保持一致
    private func restoreLastActivity() {
        for index in characters.indices {
            guard let snapshot = ChatHistoryStorage.load(characterID: characters[index].id),
                  let last = snapshot.messages.last else { continue }
            characters[index].lastMessage = last.text
            characters[index].lastActivity = last.date
        }
    }

    var totalUnread: Int {
        characters.reduce(0) { $0 + $1.unread }
    }

    func character(id: String) -> Character? {
        characters.first { $0.id == id }
    }

    /// 首页推荐池：官方角色 + 用户创建的角色，每次进入随机洗牌，
    /// 保证「每次进 App 都能遇到新面孔」。
    func recommendationFeed() -> [Character] {
        // 用户创建的角色还没有对应角色 → 现场物化并进池。
        // 必须按 id 判断：名字是展示用的，两个作者都可能叫「小助理」
        for agent in myAgents {
            let stableID = Self.localAgentID(agent.name)
            if !characters.contains(where: { $0.id == stableID }) {
                chatCharacter(for: agent)
            }
        }
        // 云端公开的角色也进推荐（别人发布的，你能刷到）
        let cloud = cloudCharacters.filter { item in
            !characters.contains(where: { $0.id == item.id })
        }
        return (characters + cloud).shuffled()
    }

    /// 登录后拉一次云端公开角色
    func refreshCloudAgents() async {
        guard CloudSession.shared.isLoggedIn else {
            cloudCharacters = []
            return
        }
        guard let list = try? await CloudAgents.fetchPublished() else { return }
        cloudCharacters = list.enumerated().map { Character.cloud($0.element, index: $0.offset) }
    }

    func markRead(_ id: String) {
        guard let index = characters.firstIndex(where: { $0.id == id }) else { return }
        characters[index].unread = 0
    }

    func toggleLike(_ id: String) {
        guard let index = characters.firstIndex(where: { $0.id == id }) else { return }
        characters[index].liked.toggle()
        characters[index].likeCount += characters[index].liked ? 1 : -1
    }

    func touchConversation(id: String, lastMessage: String) {
        guard let index = characters.firstIndex(where: { $0.id == id }) else { return }
        characters[index].lastMessage = lastMessage
        characters[index].lastActivity = Date()
    }

    func makeChatModel(for character: Character) -> ChatModel {
        ChatModel(character: character, service: activeService)
    }

    func saveProfile(_ profile: UserProfile) {
        self.profile = profile
        ProfileStorage.save(profile)
    }

    @discardableResult
    func createAgent(from draft: AgentDraft) -> MyAgent {
        let agent = MyAgent(
            name: draft.nickname,
            summary: draft.intro,
            setting: draft.setting,
            voiceName: draft.voice,
            views: 0,
            imageName: draft.imageName,
            hue: draft.hue,
            saturation: draft.saturation
        )
        myAgents.insert(agent, at: 0)
        showToast("角色「\(agent.name)」已创建")
        return agent
    }

    /// 高光时刻卡片 → 可对话的角色。没有则从人设资料动态创建并加入列表。
    @discardableResult
    /// 自定义角色的稳定 id：名字是唯一能跨启动保持稳定的东西，但要限定在本地命名空间里，
    /// 避免和云端角色（cloud-<数字 id>）撞车
    static func localAgentID(_ name: String) -> String {
        "agent-\(name.trimmingCharacters(in: .whitespaces))"
    }

    func chatCharacter(for agent: MyAgent) -> Character {
        let stableID = Self.localAgentID(agent.name)
        // 按 id 找，不能按名字找：否则同名的云端角色会被当成这个本地角色，
        // 聊天记录会写到 cloud-<id> 上，两个人互相串
        if let existing = characters.first(where: { $0.id == stableID }) {
            return existing
        }
        if let index = myAgents.firstIndex(where: { $0.id == agent.id }) {
            myAgents[index].views += 1
        }
        let palettes: [(hue: Double, sat: Double)] = [
            (0, 1), (160, 0.85), (-40, 1.05), (90, 0.9), (-120, 0.95), (220, 0.8)
        ]
        let palette = palettes[abs(agent.name.hashValue) % palettes.count]
        let character = Character(
            // 用名字拼稳定 id：MyAgent.id 是每次启动新生成的 UUID，
            // 拿它拼 id 会导致每次重启聊天记录都落到新 key 上（像被清空）
            id: stableID,
            name: agent.name,
            author: "@\(profile.nickname)",
            imageName: agent.imageName ?? "char_shenjinghan",
            hue: agent.imageName == nil ? palette.hue : agent.hue,
            saturation: agent.imageName == nil ? palette.sat : agent.saturation,
            tags: ["自定义"],
            bio: agent.summary,
            opening: agent.summary.isEmpty
                ? "（抬起头，目光落到你身上）来了。坐吧。"
                : "（抬起头，放下手边的事）你来啦。我是\(agent.name)——\(agent.summary)",
            replies: [],
            voiceKind: VoiceKind.kind(for: agent.voiceName),
            voiceName: agent.voiceName,
            likeCount: 0,
            unread: 0,
            // 没有对话记录就不该出现在「热聊」里，也别把时间写成“现在”
            lastMessage: "",
            lastActivity: .distantPast
        )
        // 如果之前聊过，把真实的最后一条记录接回来
        if let snapshot = ChatHistoryStorage.load(characterID: character.id),
           let last = snapshot.messages.last {
            var updated = character
            updated.lastMessage = last.text
            updated.lastActivity = last.date
            characters.append(updated)
        } else {
            characters.append(character)
        }
        return character
    }

    func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(Motion.smooth) { toast = text }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.quick) { self?.toast = nil }
        }
    }
}

enum ProfileStorage {
    private static let key = "user.profile"

    /// 逐字段容错读取：老版本存的 JSON 少字段时，不要整份丢掉回默认值，
    /// 否则用户改过的个性签名/昵称会「莫名回到默认」。
    static func load() -> UserProfile {
        var profile = UserProfile()
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return profile
        }
        profile.nickname = dict["nickname"] as? String ?? profile.nickname
        profile.accountID = dict["accountID"] as? String ?? profile.accountID
        profile.gender = dict["gender"] as? String ?? profile.gender
        profile.city = dict["city"] as? String ?? profile.city
        profile.signature = dict["signature"] as? String ?? profile.signature
        profile.isLoggedIn = dict["isLoggedIn"] as? Bool ?? profile.isLoggedIn
        return profile
    }

    static func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
