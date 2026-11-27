import Foundation

/// 保存设定时检查是否和角色原人设直接矛盾。
/// 不拦着用户改——只是让他知道「这条会覆盖原来的设定」，避免他以为没生效。
@MainActor
enum LoreConflictChecker {

    static func check(content: String, bio: String) async -> String? {
        let cleanBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LLMSettings.shared.isReady, !cleanBio.isEmpty, !content.isEmpty else { return nil }

        let system = """
        判断「新设定」是否与「原人设」在同一件事上给出不同答案（直接矛盾）。
        直接矛盾举例：原人设说想当漫画家，新设定说毕业后做心理咨询。
        不矛盾举例：原人设说性格冷淡，新设定补充他怕水。
        如果矛盾，输出一句不超过 18 字的说明，指出矛盾点；
        如果不矛盾，只输出 NONE。不要输出其他任何内容。
        """
        let user = "原人设：\(cleanBio.prefix(300))\n新设定：\(content)"

        guard let raw = try? await LLMClient.completeOnce(system: system, user: user, temperature: 0.1) else {
            return nil
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.uppercased().contains("NONE") { return nil }
        return String(text.prefix(40))
    }
}
