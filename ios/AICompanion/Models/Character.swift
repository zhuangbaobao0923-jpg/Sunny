import Foundation

struct Character: Identifiable, Hashable {
    let id: String
    let name: String
    let author: String
    let imageName: String
    /// 立绘色相偏移（复用素材时区分不同角色）
    var hue: Double = 0
    var saturation: Double = 1
    let tags: [String]
    let bio: String
    let opening: String
    let replies: [String]
    /// 声音画像（TTS 音色）
    var voiceKind: VoiceKind = .softGirl
    var likeCount: Int
    var liked: Bool = false
    var unread: Int
    var lastMessage: String
    var lastActivity: Date
}

struct MyAgent: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let summary: String
    var setting: String
    var voiceName: String?
    var views: Int
    var imageName: String?
    /// 形象方案的渲染参数（视觉区分不同方案）
    var hue: Double = 0
    var saturation: Double = 1
}

struct UserProfile: Equatable, Codable {
    var nickname: String = "御剑恐高的仙人"
    var accountID: String = "Aurora-8891"
    var gender: String = "男"
    var city: String = "深圳"
    var signature: String = "星星点灯，照亮了我的家门"
    var isLoggedIn: Bool = true

    var initial: String { String(nickname.prefix(1)) }
}

/// 生成中的草稿（创建智能体表单）
struct AgentDraft {
    var imageName: String?
    var hue: Double = 0
    var saturation: Double = 1
    var voice: String?
    var bgm: String?
    var nickname: String = ""
    var gender: String?
    var setting: String = ""
    var intro: String = ""
    var opening: String = ""

    var isVoiceMissing: Bool { voice == nil }
    var missingFields: [String] {
        var result: [String] = []
        if nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append("昵称") }
        if gender == nil { result.append("性别") }
        if setting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append("智能体设定") }
        if intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append("对外简介") }
        if opening.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append("开场白") }
        if voice == nil { result.append("智能体声音") }
        return result
    }
    var canSubmit: Bool { missingFields.isEmpty }
}
