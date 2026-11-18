import AVFoundation

// MARK: - 设备内置语音目录

/// iPhone 自带的中文语音（离线、永久可用、零成本）。
/// 用户在「设置 → 辅助功能 → 朗读内容 → 声音 → 中文」里下载增强/高级音色后，
/// 这里会自动识别并优先使用——这是「随时可用」的最后一道保障，不依赖 Mac、不依赖网络。
struct SystemVoiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let quality: Int      // 1 默认 / 2 增强 / 3 高级
    let isMale: Bool

    var qualityLabel: String {
        switch quality {
        case 3: return "高级"
        case 2: return "增强"
        default: return "标准"
        }
    }

    var displayName: String { "\(name) · \(qualityLabel)" }
}

enum SystemVoiceCatalog {
    /// 已知的女性音色名（用于给男角色挑音色时避开）
    private static let femaleMarkers = ["ting", "yu-shu", "mei-jia", "sin-ji", "xiaoxiao", "xiaoyi", "li-mu's sister",
                                        "flo", "grandma", "sandy", "shelley", "whisper", "wobble",
                                        "田田", "婷婷", "语舒", "月", "岚岚", "黎潋", "莉莉", "莎莎", "珊珊", "陶陶"]
    /// 已知的男性音色名（新版 iOS 显示为中文：李牧即旧版「立民/Li-mu」）
    private static let maleMarkers = ["li-mu", "limu", "yunxi", "yunjian", "yunyang", "yunxia", "male",
                                      "grandpa", "reed", "eddy", "rocko", "bozo", "jester",
                                      "李牧", "瀚", "彬彬", "理生"]

    /// 所有已安装的中文语音，按质量从高到低
    static func chinese() -> [SystemVoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh") }
            .map { voice in
                let lower = voice.name.lowercased()
                let male = maleMarkers.contains { lower.contains($0) }
                    && !femaleMarkers.contains { lower.contains($0) }
                return SystemVoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    quality: voice.quality.rawValue,
                    isMale: male
                )
            }
            .sorted { ($0.quality, $0.isMale ? 1 : 0) > ($1.quality, $1.isMale ? 1 : 0) }
    }

    /// 给某个角色音色挑最合适的系统语音：男角色优先男声，其次按质量取最高
    static func best(for kind: VoiceKind) -> AVSpeechSynthesisVoice? {
        let wantMale = kind.gender == "男"
        let options = chinese()
        let picked = options.first { $0.isMale == wantMale } ?? options.first
        guard let id = picked?.id else { return AVSpeechSynthesisVoice(language: "zh-CN") }
        return AVSpeechSynthesisVoice(identifier: id) ?? AVSpeechSynthesisVoice(language: "zh-CN")
    }

    /// 男角色是否选中了真正的男声（决定了要不要额外压低音调）
    static func isMaleVoice(_ voice: AVSpeechSynthesisVoice?) -> Bool {
        guard let name = voice?.name.lowercased() else { return false }
        return maleMarkers.contains { name.contains($0) }
    }

    /// 设置页一句话结论
    static func summary() -> String {
        let options = chinese()
        guard !options.isEmpty else { return "未检测到中文语音" }
        let hasEnhanced = options.contains { $0.quality >= 2 }
        let hasMale = options.contains { $0.isMale }
        if hasEnhanced && hasMale { return "已具备增强音色与男声，离线即可播放" }
        if hasEnhanced { return "已有增强音色，但缺少男声（可按下方指引下载「李牧」）" }
        if hasMale { return "已有男声，但音色为标准质量（可下载「李牧·优化音质」提升音质）" }
        return "仅标准音色；按下方指引免费下载「李牧」（男声）后男角色音质明显提升"
    }
}
