import Foundation

// MARK: - 跨会话聊天记忆

/// 一次完整的对话回合（用户输入 + 角色回复）
struct MemoryTurn: Codable, Equatable {
    var user: String
    var reply: String
    var date: Date
}

/// 按角色持久化最近对话，实现「退出再进来也记得聊过什么」。
/// 存 UserDefaults（轻量、同步读写）；接真后端后由服务端会话摘要替代。
final class ChatMemoryStore {
    static let shared = ChatMemoryStore()

    private var key: String { "chat.memory.turns.\(AccountScope.id)" }
    private let legacyKey = "chat.memory.turns"
    private let maxTurnsPerCharacter = 12
    private let defaults: UserDefaults
    private var cache: [String: [MemoryTurn]]

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let scopedKey = "chat.memory.turns.\(AccountScope.id)"
        if let data = defaults.data(forKey: scopedKey),
           let decoded = try? JSONDecoder().decode([String: [MemoryTurn]].self, from: data) {
            cache = decoded
        } else if let legacy = defaults.data(forKey: legacyKey),
                  let decoded = try? JSONDecoder().decode([String: [MemoryTurn]].self, from: legacy) {
            // 老数据迁移到当前账号
            cache = decoded
            if let data = try? JSONEncoder().encode(decoded) {
                defaults.set(data, forKey: scopedKey)
            }
        } else {
            cache = [:]
        }
    }

    func turns(for characterID: String) -> [MemoryTurn] {
        cache[characterID] ?? []
    }

    /// 记录一回合；与上一条完全相同则去重（重试场景）
    func record(characterID: String, user: String, reply: String) {
        record(characterID: characterID, user: user, reply: reply, date: Date())
    }

    /// 可注入时间的版本（单元测试模拟「几小时前 / 三天前聊过」）
    func record(characterID: String, user: String, reply: String, date: Date) {
        var turns = turns(for: characterID)
        let turn = MemoryTurn(user: user, reply: reply, date: date)
        guard turns.last != turn else { return }
        turns.append(turn)
        if turns.count > maxTurnsPerCharacter {
            turns.removeFirst(turns.count - maxTurnsPerCharacter)
        }
        cache[characterID] = turns
        persist()
    }

    func clear(characterID: String) {
        cache[characterID] = nil
        persist()
    }

    // MARK: 认识时间（给时间锚用）

    private var firstSeenKey: String { "chat.firstSeen.\(AccountScope.id)" }

    /// 第一次聊天时记一笔，用来算「认识第几天」
    func markFirstSeen(characterID: String, date: Date = Date()) {
        var map = (defaults.dictionary(forKey: firstSeenKey) as? [String: Date]) ?? [:]
        guard map[characterID] == nil else { return }
        // 老用户：用能查到的最早一回合兜底，别让「认识第 1 天」出现在聊了很久的人身上
        let earliest = turns(for: characterID).first?.date ?? date
        map[characterID] = min(earliest, date)
        defaults.set(map, forKey: firstSeenKey)
    }

    func firstSeen(characterID: String) -> Date? {
        (defaults.dictionary(forKey: firstSeenKey) as? [String: Date])?[characterID]
    }

    /// 距上一回合过去了多少小时；无记忆返回 nil（72 小时记忆窗口的判断依据）
    func gapHours(for characterID: String) -> Double? {
        guard let last = turns(for: characterID).last else { return nil }
        return Date().timeIntervalSince(last.date) / 3600
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - 文本分析工具

enum ChatText {
    /// 是否纯数字（含全角数字）
    static func isNumeric(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    /// 是否超短输入（1-2 字、单个表情等）
    static func isUltraShort(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count <= 2
    }

    /// 提取可引用的关键词：去标点 → 去口头虚词 → 取主体词（长句取前 2 字，短词全取）
    static func salientKeyword(from text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 4 else { return nil }
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
        t = t.unicodeScalars.filter { !punctuation.contains($0) }.map(String.init).joined()
        let fillers = ["要不要", "是不是", "有没有", "为什么", "怎么样", "可以不可以", "如果", "因为", "所以", "但是", "其实", "就是", "感觉", "好像", "今天", "明天", "昨天", "现在", "最近", "你说", "我想", "请问", "总是", "老是", "一直", "特别", "非常", "有点", "一点", "真的", "真是"]
        for f in fillers { t = t.replacingOccurrences(of: f, with: "") }
        let particles = "的吗呢吧啊呀哦嘛了呀吖咯喽哟嗯"
        while let last = t.last, particles.contains(String(last)) {
            t.removeLast()
        }
        guard t.count >= 2 else { return nil }
        // 长句（≥5 字）取末尾 3 字（中文宾语常在尾部，如「学做桂花糕」→「桂花糕」）；中短句全取
        guard t.count >= 2 else { return nil }
        var keyword = t.count >= 5 ? String(t.suffix(3)) : t
        // 剔除句尾引导虚字：「才成功」→「成功」
        let leadingFillers = "才就都也又还刚很挺太"
        while let first = keyword.first, leadingFillers.contains(String(first)), keyword.count > 2 {
            keyword.removeFirst()
        }
        return keyword
    }

    /// 识别「用户离开时说要去做的事」：`我去忙了`「先去上课」→ 待办事件词
    /// 用于跨会话接续时主动追问：「你刚才去忙的事办完了？」
    static func pendingEvent(from text: String) -> String? {
        let triggers: [(String, String)] = [
            ("去忙", "去忙的事"), ("忙去了", "去忙的事"), ("干活", "要干的活"),
            ("上班", "班"), ("上课", "课"), ("开会", "会"), ("考试", "考试"),
            ("去睡", "觉"), ("洗澡", "澡"), ("吃饭", "饭"), ("干饭", "饭"),
            ("做饭", "饭"), ("训练", "训练"), ("出门", "要出门办的事"),
            ("先走", "去忙的事"), ("去一趟", "要去办的事")
        ]
        for (trigger, label) in triggers where text.contains(trigger) {
            // 关键词必须是比触发词更具体的宾语（如「先去上奥数课」→「奥数课」），否则退回通用标签
            if let kw = salientKeyword(from: text), kw.contains(trigger), kw.count <= 3 {
                return kw
            }
            return label
        }
        return nil
    }

    /// 当前时段短语（活人感：接话时自然带出时间语境）
    static func timePhrase() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<9: return "清晨"
        case 9..<12: return "上午"
        case 12..<14: return "午后"
        case 14..<18: return "下午"
        case 18..<23: return "夜里"
        default: return "深夜"
        }
    }
}

// 72 小时记忆窗口判断已内联到 PersonaEngine.returnGreeting / ChatMemoryStore.gapHours
