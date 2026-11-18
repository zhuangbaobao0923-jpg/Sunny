import Foundation

// MARK: - 人设 → System Prompt

/// 把角色卡、亲密度、跨会话记忆拼成一段 System Prompt。
/// 这是 App 的「人格内核」：换成任何 OpenAI 兼容模型，说话风格都保持一致。
enum PersonaPrompt {

    static func system(
        for character: Character,
        level: Int,
        memory: [MemoryTurn]
    ) -> String {
        var lines: [String] = []
        lines.append("你在扮演一个虚构角色，与用户进行第一人称的沉浸式对话。")
        lines.append("")
        lines.append("【角色】\(character.name)")
        if !character.tags.isEmpty {
            lines.append("【题材】\(character.tags.joined(separator: " / "))")
        }
        lines.append("【人设】\(character.bio)")

        if !character.replies.isEmpty {
            lines.append("【说话风格参考】以下是你曾说过的话，用词、语气、句子长短必须与之一致：")
            for reply in character.replies.prefix(3) {
                lines.append("- \(reply)")
            }
        }

        lines.append("")
        lines.append("【硬性规则】")
        lines.append("1. 你就是\(character.name)本人，永远用第一人称说话，不要自称 AI、模型、助手、机器人。")
        lines.append("2. 每次回复 1~2 句，总长度 15~60 个汉字，口语化。禁止长篇独白、禁止总结、禁止列点。")
        lines.append("3. 可以在句首或句中用全角括号（）写动作、神态、心理，例如（垂眸，指尖敲了敲桌面）。")
        lines.append("4. 不要复述用户的话，不要问“有什么可以帮你”，不要解释设定。")
        lines.append("5. 不要输出 Markdown、列表、表情符号、标题。只输出角色要说的话。")
        lines.append("6. 顺着用户的话题往下演，可以反问、可以沉默、可以拒绝，但保持角色人设不崩。")
        lines.append("7. 除非用户先提起，不要主动提到自己是虚构角色或这个故事之外的任何事。")
        lines.append("")
        lines.append("【当前关系】亲密度 Lv.\(level)：\(levelHint(for: level))")

        if !memory.isEmpty {
            lines.append("")
            lines.append("【记忆】你和用户之前聊过（时间由远到近），可以自然承接，但不要生硬复述：")
            for turn in memory.suffix(3) {
                lines.append("- \(timePhrase(for: turn.date))，用户说：\(shorten(turn.user))；你回：\(shorten(turn.reply))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 组装成 OpenAI 兼容的 messages 数组
    static func messages(
        for character: Character,
        history: [ChatMessage],
        userText: String,
        level: Int,
        memory: [MemoryTurn]
    ) -> [[String: String]] {
        var result: [[String: String]] = [
            ["role": "system", "content": system(for: character, level: level, memory: memory)]
        ]
        // 开场白（第一条 assistant）作为气氛铺垫保留；失败气泡不入上下文
        for message in history where !message.failed && !message.text.isEmpty {
            result.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": message.text
            ])
        }
        // 保证最后一条一定是本次用户输入（避免历史里已含同一句导致重复）
        if result.last?["content"] != userText || result.last?["role"] != "user" {
            result.append(["role": "user", "content": userText])
        }
        return result
    }

    private static func levelHint(for level: Int) -> String {
        switch level {
        case 1: return "刚认识，语气克制、有距离感，不主动示好。"
        case 2: return "开始熟悉，会主动关心一两句，但仍端着。"
        case 3: return "已经亲近，肯露出一点情绪，偶尔调侃。"
        case 4: return "相当依赖，会主动说自己的事、会护着用户。"
        default: return "心意相通，语气可以亲密、纵容，但不要油腻。"
        }
    }

    private static func timePhrase(for date: Date) -> String {
        let hours = Date().timeIntervalSince(date) / 3600
        switch hours {
        case ..<1: return "刚才"
        case ..<24: return "\(Int(hours)) 小时前"
        case ..<48: return "昨天"
        default: return "\(Int(hours / 24)) 天前"
        }
    }

    private static func shorten(_ text: String, limit: Int = 40) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        return clean.count > limit ? String(clean.prefix(limit)) + "…" : clean
    }
}
