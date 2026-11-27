import Foundation

/// 规则抽取（方案 A 的底座）：只从**用户自己说的话**里挑候选句，
/// 改写成「用户……」的条目。不做自由生成，宁可少记，也不编造。
enum MemoryExtractor {

    /// 触发词：命中才认为这句话里可能有值得记的事实
    private static let triggers = [
        "我叫", "我是", "我养", "我家", "我住", "我在", "我喜欢", "我讨厌", "我怕",
        "我最近", "我每天", "我妈", "我爸", "我女朋友", "我男朋友", "我生日", "我在做"
    ]

    /// 常见话题词：不靠分词，用一张小词表兜住最常聊到的实体
    private static let topics = [
        "猫", "狗", "宠物", "加班", "失眠", "工作", "公司", "学校", "同事", "室友",
        "妈妈", "爸爸", "生日", "咖啡", "游戏", "音乐", "电影", "旅行", "房租",
        "考试", "健身", "医院", "吃药", "下雨", "冬天", "分手", "相亲", "面试"
    ]

    /// 从一轮用户输入里抽条目（同步、纯本机；失败不影响聊天）
    @discardableResult
    static func extract(from text: String, characterID: String) -> [MemoryEntry] {
        let found = candidates(from: text)
        var saved: [MemoryEntry] = []
        for var entry in found {
            entry.characterID = characterID
            saved.append(MemoryStore.shared.upsert(entry))
        }
        return saved
    }

    static func candidates(from text: String, now: Date = Date()) -> [MemoryEntry] {
        let clauses = text
            .components(separatedBy: CharacterSet(charactersIn: "。！？!?；;\n"))
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: "，,")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result: [MemoryEntry] = []
        for clause in clauses {
            // 问句不算事实（「你养猫了吗」）
            if clause.contains("吗") || clause.contains("?") || clause.contains("？") { continue }
            guard clause.count >= 4, clause.count <= 40 else { continue }
            guard let trigger = triggers.first(where: { clause.contains($0) }) else { continue }

            let content = rewrite(clause)
            guard content.count >= 4 else { continue }
            let keys = keywords(in: clause, trigger: trigger)
            guard !keys.isEmpty else { continue }

            result.append(MemoryEntry(
                characterID: "",
                keys: keys,
                content: content,
                weight: weight(for: clause),
                createdAt: now,
                source: .rule
            ))
        }
        return result
    }

    // MARK: 内部

    /// 第一人称改成「用户」，读起来像一条设定，而不是复读原话
    private static func rewrite(_ clause: String) -> String {
        var text = clause
        for prefix in ["然后", "就是", "其实", "对了"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        if text.hasPrefix("我") {
            text = "用户" + text.dropFirst()
        } else {
            text = "用户说：" + text
        }
        return String(text.prefix(40))
    }

    private static func weight(for clause: String) -> Double {
        let important = ["怕", "讨厌", "喜欢", "生日", "妈妈", "爸爸", "分手", "医院"]
        return important.contains(where: { clause.contains($0) }) ? 1.4 : 1.0
    }

    /// 命中词：优先取「叫 X」里的名字，其次取触发词后面的短词，再补话题词
    private static func keywords(in clause: String, trigger: String) -> [String] {
        var keys: [String] = []

        if let range = clause.range(of: "叫") {
            let name = clause[range.upperBound...]
                .prefix(4)
                .trimmingCharacters(in: CharacterSet(charactersIn: "，。的了吧呢啊"))
            if !name.isEmpty { keys.append(name) }
        }

        if let range = clause.range(of: trigger) {
            let tail = clause[range.upperBound...]
                .prefix(8)
                .trimmingCharacters(in: CharacterSet(charactersIn: "，。的了吧呢啊来着"))
            let cleaned = tail
                .replacingOccurrences(of: "了", with: "")
                .replacingOccurrences(of: "一只", with: "")
                .replacingOccurrences(of: "一个", with: "")
            if cleaned.count >= 2 { keys.append(String(cleaned.prefix(4))) }
        }

        for topic in topics where clause.contains(topic) {
            keys.append(topic)
        }

        // 去重、去空、最多 4 个，避免命中词太泛导致永远被带进上下文
        var seen = Set<String>()
        return keys
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .prefix(4)
            .map { $0 }
    }
}
