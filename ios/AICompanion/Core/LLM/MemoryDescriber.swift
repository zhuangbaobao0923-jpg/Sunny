import Foundation

/// P2：用一个小模型把「用户的原话」改写成一条可长期记住的事实。
///
/// 设计上刻意收得很紧：
/// - 只有规则先筛出候选（命中触发词）才去打扰模型，普通闲聊不产生额外请求；
/// - 只允许改写这句话里的信息，不允许自由发挥（prompt 里写死）；
/// - 模型失败/没配 Key → 自动退回 P1 的规则结果，功能不降级。
enum MemoryDescriber {

    @MainActor
    static func extract(from text: String, characterID: String) async {
        let seeds = MemoryExtractor.candidates(from: text)
        // 没有触发词 = 这句话不像在讲自己的事，省一次请求
        guard !seeds.isEmpty else { return }

        guard LLMSettings.shared.isReady else {
            save(seeds, characterID: characterID, source: .rule)
            return
        }

        switch await describe(text) {
        case .success(let entries):
            if entries.isEmpty {
                // 模型判断「没什么值得记的」→ 尊重它，不要拿规则结果凑数
                return
            }
            save(entries, characterID: characterID, source: .model)
        case .failure:
            save(seeds, characterID: characterID, source: .rule)
        }
    }

    // MARK: 模型

    private enum Result {
        case success([MemoryEntry])
        case failure
    }

    @MainActor
    private static func describe(_ text: String) async -> Result {
        let system = """
        你在做「长期记忆抽取」。输入是用户刚说的一句话，输出值得长期记住的信息。
        规则：
        - 只抽关于用户本人的稳定信息：身份、家人、宠物、喜好、恐惧、工作、住址、生日、长期习惯。
        - 不抽临时安排（今晚加班）、情绪（今天好累）、问句、对 AI 的指令。
        - content 改写成第三人称短句，以「用户」开头，不超过 30 个字，一句话只讲一件事。
        - keys 是 1~3 个命中词，必须是原文里出现过的词，不要自己造。
        - 最多 2 条；如果没有值得记的，输出 []。
        只输出 JSON 数组，不要 Markdown、不要解释。
        例：[{"content":"用户养了一只猫，叫团子","keys":["猫","团子"]}]
        """
        do {
            let raw = try await LLMClient.completeOnce(system: system, user: text, temperature: 0.2)
            guard let entries = parse(raw) else { return .failure }
            return .success(entries)
        } catch {
            return .failure
        }
    }

    /// 容错解析：模型偶尔会套 ```json 或前后带解释，这里只抓第一个数组
    static func parse(_ raw: String) -> [MemoryEntry]? {
        guard let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]"),
              start < end else { return nil }
        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        var result: [MemoryEntry] = []
        for row in rows {
            guard let content = (row["content"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !content.isEmpty else { continue }
            let keys = (row["keys"] as? [String] ?? [])
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !keys.isEmpty else { continue }
            result.append(MemoryEntry(
                characterID: "",
                keys: Array(keys.prefix(4)),
                content: String(content.prefix(40)),
                weight: weight(for: content),
                source: .model
            ))
            if result.count >= 2 { break }
        }
        return result
    }

    private static func weight(for content: String) -> Double {
        let important = ["怕", "讨厌", "喜欢", "生日", "妈妈", "爸爸", "家人", "分手", "医院"]
        return important.contains(where: { content.contains($0) }) ? 1.4 : 1.0
    }

    private static func save(_ entries: [MemoryEntry], characterID: String, source: MemoryEntry.Source) {
        for var entry in entries {
            entry.characterID = characterID
            entry.source = source
            MemoryStore.shared.upsert(entry)
        }
    }
}
