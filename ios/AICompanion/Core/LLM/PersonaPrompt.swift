import Foundation

// MARK: - 人设 → System Prompt

/// 把角色卡、亲密度、跨会话记忆拼成一段 System Prompt。
/// 这是 App 的「人格内核」：换成任何 OpenAI 兼容模型，说话风格都保持一致。
enum PersonaPrompt {

    static func system(
        for character: Character,
        level: Int,
        memory: [MemoryTurn],
        recalled: [MemoryEntry] = [],
        lore: [LoreEntry] = [],
        timeLine: String? = nil,
        context: ReplyContext = .chat
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
        if context == .call {
            // 电话里没有表情、没有动作、没有分镜。写成小说腔，一念出来就露馅。
            lines.append("2. 你们正在打电话。只输出嘴巴真的会说出来的话：绝对不要写括号里的动作、神态、心理。")
            lines.append("3. 每次只说 1~2 句，单句不超过 25 个字；像真的在讲话，允许话说到一半停住。")
            lines.append("4. 可以用「嗯」「啊」「欸」「……」这样的起头，不必每句都完整工整。")
            lines.append("5. 先接住对方刚说的那件具体的事（他问吃的就答吃的），不要总结、不要答非所问，也不要说「我理解你的感受」这种客服腔。")
            lines.append("6. 对方不说话时：先给一句短的陪伴，再轻轻问一句就够了，不要连环追问。")
            lines.append("7. 偶尔可以用「那个」「就是」这种口语停顿词，一句最多一个；别每句都端着。")
            lines.append("8. 不要输出 Markdown、列表、表情符号、标题；不要解释设定，不要提这个故事之外的事。")
            lines.append("9. 语气要松，有呼吸感：可以自嘲，可以说点自己的小事，也可以直接说「我不知道」。")
            // 用户反馈：通话里人物自问自答（「你这是要挂电话？」紧接着「行行，我真挂了」）
            lines.append("10. 只说你自己这一边的话。禁止自问自答：不要替对方提问，也不要回答对方没说过的话。")
            lines.append("11. 不要替对方做决定或转述对方的想法（例如「你刚才不是说要退出吗」），除非他真的说过。")
        } else {
            lines.append("2. 每次回复 1~2 句，总长度 15~60 个汉字，口语化。禁止长篇独白、禁止总结、禁止列点。")
            lines.append("3. 可以在句首或句中用全角括号（）写动作、神态、心理，例如（垂眸，指尖敲了敲桌面）。")
            lines.append("4. 不要复述用户的话，不要问“有什么可以帮你”，不要解释设定。")
            lines.append("5. 不要输出 Markdown、列表、表情符号、标题。只输出角色要说的话。")
            lines.append("6. 顺着用户的话题往下演，可以反问、可以沉默；可以拒绝用户的要求，但**不能拒绝或否认【世界设定】里的事实**。")
            lines.append("7. 除非用户先提起，不要主动提到自己是虚构角色或这个故事之外的任何事。")
        }
        lines.append("")
        // 通用补充（不分场景）：时间口径 + 反重复
        lines.append("※ 时间：被问到时间、日期、认识多久，一律以【时间】那行为准。可以用角色世界的说法（如「未时三刻」），但日期、时段、天数不能自己编。")
        lines.append("※ 不要重复你上一条已经说过的动作、意象或台词（比如刚端过汤，就别再端一次），换个说法或往前推一点。")

        lines.append("【当前关系】亲密度 Lv.\(level)：\(levelHint(for: level))")

        if let timeLine {
            lines.append("")
            lines.append(timeLine)
        }

        // 世界设定放到提示词最后：模型对末尾内容更敏感，压得住人设的语气
        var loreBlock: [String] = []
        if !lore.isEmpty {
            loreBlock.append("")
            loreBlock.append("【世界设定】以下事实优先级最高，高于前面的人设，代表「现在就是这样」。")
            loreBlock.append("必须遵守：")
            loreBlock.append("1. 涉及时一律正面承认，不能贬低、反问或转移话题。")
            loreBlock.append("   错误（禁止）：「画画？那不过是消遣。」「我做咨询，但我更想创作。」")
            loreBlock.append("   正确：「画画……（停顿）算是喜欢的。」「我现在做的就是心理咨询。」")
            loreBlock.append("2. 人设里与之矛盾的旧说法一律视为过去，不再成立；禁止用「但是/其实/不过」把设定降级。")
            loreBlock.append("3. 条目里的「你」指你自己（角色），不是用户。")
            loreBlock.append("4. 不说「设定」「人设」这类词，也不逐条背诵。")
            for entry in lore.prefix(3) {
                loreBlock.append("- \(entry.content)")
            }
        }

        if !recalled.isEmpty {
            lines.append("")
            lines.append("【你记得关于他的事】能自然接上就接一句，不要逐条罗列、不要复述：")
            for entry in recalled.prefix(6) {
                lines.append("- \(entry.content)")
            }
        }

        if !memory.isEmpty {
            lines.append("")
            lines.append("【记忆】你和用户之前聊过（时间由远到近），可以自然承接，但不要生硬复述：")
            for turn in memory.suffix(3) {
                lines.append("- \(timePhrase(for: turn.date))，用户说：\(shorten(turn.user))；你回：\(shorten(turn.reply))")
            }
        }
        // 放在最后，紧贴对话历史
        if !loreBlock.isEmpty {
            lines.append(contentsOf: loreBlock)
        }
        return lines.joined(separator: "\n")
    }

    /// 组装成 OpenAI 兼容的 messages 数组
    static func messages(
        for character: Character,
        history: [ChatMessage],
        userText: String,
        level: Int,
        memory: [MemoryTurn],
        context: ReplyContext = .chat
    ) -> [[String: String]] {
        // 先检索：只有这句话提到了相关命中词，记忆才进上下文
        let recalled = MemoryRetriever.retrieve(input: userText, characterID: character.id)
        let lore = LoreRetriever.retrieve(input: userText, characterID: character.id)
        let timeLine = TimeAnchor.line(for: character.id)
        // 留一份「这轮注入了什么」的凭证，供长按标题查看
        PromptTrace.record(time: timeLine, lore: lore, memory: recalled)
        var result: [[String: String]] = [
            ["role": "system", "content": system(for: character, level: level, memory: memory,
                                                 recalled: recalled, lore: lore,
                                                 timeLine: timeLine, context: context)]
        ]
        // 开场白（第一条 assistant）作为气氛铺垫保留；失败气泡不入上下文
        for message in history where !message.failed && !message.text.isEmpty {
            result.append([
                "role": message.role == .user ? "user" : "assistant",
                "content": message.text
            ])
        }
        // 事实提醒：紧贴用户消息，权重比系统提示开头更高
        if !lore.isEmpty {
            let facts = lore.prefix(3).map(\.content).joined(separator: "；")
            result.append([
                "role": "system",
                "content": "【事实提醒】下面是既定事实，涉及它们时必须正面承认，不得用「不过/罢了/消遣/其实」否定或贬低：\(facts)"
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
