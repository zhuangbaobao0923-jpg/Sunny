import Foundation

/// 关键词自动补全：用户只写「这条设定是什么」，系统替他想「用户会怎么问」。
/// C 端不能让用户自己猜关键词——填了设定却永远不生效，等于没填。
@MainActor
enum LoreKeywordExpander {

    static func expand(title: String, content: String) async -> [String] {
        guard LLMSettings.shared.isReady else { return fallback(title: title, content: content) }

        let system = """
        你在给一条「角色设定」生成触发词。
        用户会在聊天里用各种说法提到这条设定，你要覆盖这些说法。
        规则：
        - 输出 8~12 个中文词或短语，每个 2~6 个字。
        - 必须包含同义说法、口语说法、相关场景。例如设定是「她毕业后做心理咨询」，就要输出：工作、职业、上班、就业、心理、心理咨询、毕业、大学、专业、心理医生。
        - 不要输出人名、不要输出整句、不要重复。
        - 只输出 JSON 数组，不要解释。例如：["工作","职业","上班"]
        """
        let user = "标题：\(title)\n内容：\(content)"

        do {
            let raw = try await LLMClient.completeOnce(system: system, user: user, temperature: 0.3)
            let keys = parse(raw)
            return keys.isEmpty ? fallback(title: title, content: content) : keys
        } catch {
            return fallback(title: title, content: content)
        }
    }

    /// 容错解析：只抓第一个数组
    static func parse(_ raw: String) -> [String] {
        guard let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]"),
              start < end else { return [] }
        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return rows
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { (2...8).contains($0.count) }
            .reduce(into: [String]()) { result, key in
                if !result.contains(key) { result.append(key) }
            }
    }

    /// 模型不可用时的兜底：至少把标题和内容里较短的片段用上
    static func fallback(title: String, content: String) -> [String] {
        var result: [String] = []
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        if !cleanTitle.isEmpty { result.append(cleanTitle) }

        let segments = content.components(separatedBy: CharacterSet(charactersIn: "，。；、,.;：\n"))
        for segment in segments {
            let text = segment.trimmingCharacters(in: .whitespaces)
            if (2...8).contains(text.count), !result.contains(text) {
                result.append(text)
            }
            if result.count >= 8 { break }
        }
        return result
    }
}
