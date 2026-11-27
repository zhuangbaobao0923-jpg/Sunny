import Foundation

/// 世界书检索。
/// 三档含义（对用户要能讲明白）：
/// - 核心：常驻，不用命中也会带上（最多 2 条），因为它们通常定义“这个世界是什么样”
/// - 重要：命中时优先抢名额
/// - 普通：命中即注入
/// 每轮最多 3 条，避免把上下文塞满。
enum LoreRetriever {

    static func retrieve(input: String, characterID: String, limit: Int = 3) -> [LoreEntry] {
        let entries = LoreStore.shared.entries(for: characterID)
        guard !entries.isEmpty else { return [] }

        // 核心设定常驻：用户标了「核心」就是希望它一直有效，而不是排队时插队
        let constants = Array(entries.filter { $0.priority == 2 }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(2))
        let constantIDs = Set(constants.map(\.id))
        let remaining = limit - constants.count

        guard remaining > 0, !input.isEmpty else { return constants }
        let text = input.lowercased()

        var scored: [(entry: LoreEntry, score: Int)] = []
        for entry in entries where !constantIDs.contains(entry.id) {
            var hit = 0
            // 标题也是命中词：标题往往就是用户会提到的说法
            if !entry.title.isEmpty, text.contains(entry.title.lowercased()) {
                hit += entry.title.count + 2
            }
            for key in entry.keys where !key.isEmpty {
                if text.contains(key.lowercased()) {
                    hit += key.count + 2
                }
            }
            guard hit > 0 else { continue }
            scored.append((entry, hit + entry.priority * 6))
        }

        let hits = scored
            .sorted { $0.score > $1.score }
            .prefix(remaining)
            .map { $0.entry }
        return constants + hits
    }
}
