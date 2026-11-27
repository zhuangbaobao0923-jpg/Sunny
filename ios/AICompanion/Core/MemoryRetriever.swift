import Foundation

/// 检索（第一层：字面命中）。
/// 只有用户这句话里出现了条目的命中词，才把这条记忆带进上下文——
/// 不相关的时候一条都不占 token，这是「token 不涨反降」的关键。
enum MemoryRetriever {

    static func retrieve(input: String, characterID: String, limit: Int = 6) -> [MemoryEntry] {
        let entries = MemoryStore.shared.entries(for: characterID)
        guard !entries.isEmpty, !input.isEmpty else { return [] }

        let text = input.lowercased()
        var scored: [(entry: MemoryEntry, score: Double)] = []

        for entry in entries {
            var hit = 0.0
            for key in entry.keys where !key.isEmpty {
                if text.contains(key.lowercased()) {
                    // 长词更有辨识度：「团子」比「猫」更该命中
                    hit += 1 + Double(key.count) * 0.2
                }
            }
            guard hit > 0 else { continue }
            // 权重参与排序：家人/恐惧类的记忆优先把位置占住
            scored.append((entry, hit * entry.weight))
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.entry }
    }

    /// 检索并标记「用过」，用于后续做衰减/清理
    static func retrieveAndMark(input: String, characterID: String, limit: Int = 6) -> [MemoryEntry] {
        let list = retrieve(input: input, characterID: characterID, limit: limit)
        MemoryStore.shared.markUsed(ids: list.map(\.id), characterID: characterID)
        return list
    }
}
