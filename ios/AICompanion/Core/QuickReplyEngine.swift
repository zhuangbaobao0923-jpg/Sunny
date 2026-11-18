import Foundation

// MARK: - 动态对话引导词生成（提示词面板）

/// 核心规则：
/// 1. 实时上下文绑定——严禁静态套话，每次都基于【AI 角色最新发言】+【语境情绪】实时生成
/// 2. 多倾向互动分支——覆盖「顺从配合 / 试探反问 / 情绪拉扯 / 动作回应」四种心理
/// 3. 格式规范——短小精炼，「（心理/动作描述）+ 语言」，可直接填入输入框
/// 离线启发式实现；接真 LLM 后由模型按同样约束生成，接口不变。
enum QuickReplyEngine {

    /// 一条引导词 + 它代表的互动倾向（供面板打标签）
    struct Suggestion: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let tendency: Tendency

        enum Tendency: String {
            case comply = "顺从配合"
            case probe = "试探反问"
            case pull = "情绪拉扯"
            case act = "动作回应"
        }
    }

    // MARK: 语境分析

    /// AI 发言的语境类型（决定四种倾向的权重）
    private enum Context {
        case asking     // 角色在提问 / 给选择题 → 引导用户回答或反问
        case caring     // 角色在关心安抚 → 引导用户接受善意或倾诉
        case teasing    // 角色在调侃拉扯 → 引导用户反击或顺杆爬
        case inviting   // 角色在邀请 / 招呼 → 引导用户答应或讲条件
        case neutral    // 陈述 / 剧情推进 → 均衡引导
    }

    /// 最近生成过的引导词，短时间不重复（按角色记 12 条）
    private static var recentlyUsed: [String: [String]] = [:]

    /// 生成 4 条引导词（每条倾向不同，顺序随机）
    static func suggestions(for character: Character, aiMessage: String?) -> [Suggestion] {
        let speech = speechPart(of: aiMessage ?? "")
        let action = actionPart(of: aiMessage ?? "")
        let kw = sanitizedKeyword(from: speech)
        let prop = prop(in: aiMessage ?? "")
        let context = classify(speech: speech, action: action)

        let style: Style = (character.id == "swt") ? .campus : .ancient
        let pools = Self.pools(style)

        // 各倾向的权重：按语境偏置，但四个倾向都会出一条（多分支规则）
        func line(for tendency: Suggestion.Tendency, pool: [String]) -> String {
            var candidates = pool
            if kw == nil {
                let plain = candidates.filter { !$0.contains("{kw}") }
                if !plain.isEmpty { candidates = plain }
            }
            if prop == nil {
                let plain = candidates.filter { !$0.contains("{prop}") }
                if !plain.isEmpty { candidates = plain }
            }
            // 按语境把最合适的模板排前面，增加被选中的概率
            if chance(bias(of: context, for: tendency)), candidates.count > 1 {
                candidates = [candidates[0]] + candidates.dropFirst().shuffled()
            } else {
                candidates.shuffle()
            }
            var chosen = candidates.first ?? pool.randomElement() ?? "（安静地看着你）嗯。"
            // 防短时间内重复
            let used = Set(recentlyUsed[character.id] ?? [])
            if used.contains(chosen), let fresh = candidates.first(where: { !used.contains($0) }) {
                chosen = fresh
            }
            var log = recentlyUsed[character.id] ?? []
            log.append(chosen)
            if log.count > 12 { log.removeFirst(log.count - 12) }
            recentlyUsed[character.id] = log
            return chosen
                .replacingOccurrences(of: "{kw}", with: kw ?? "")
                .replacingOccurrences(of: "{prop}", with: prop ?? "")
        }

        var results: [Suggestion] = [
            .init(text: line(for: .comply, pool: pools.comply), tendency: .comply),
            .init(text: line(for: .probe, pool: pools.probe), tendency: .probe),
            .init(text: line(for: .pull, pool: pools.pull), tendency: .pull),
            .init(text: line(for: .act, pool: pools.act), tendency: .act)
        ]
        results.shuffle()
        return results
    }

    // MARK: 文本拆解

    /// 去掉（动作描写）后的纯台词部分
    private static func speechPart(of text: String) -> String {
        text.replacingOccurrences(of: "（[^）]*）", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\([^)]*\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 括号里的动作描写（用于识别场景道具/氛围）
    private static func actionPart(of text: String) -> String {
        let matches = text.matches(of: /[（(]([^）)]*)[）)]/)
        return matches.map { String($0.1) }.joined(separator: " ")
    }

    /// 从 AI 台词里提取可引用关键词；含疑问虚词的（「还是风缓」这类选择问）不算
    private static func sanitizedKeyword(from speech: String) -> String? {
        guard let kw = ChatText.salientKeyword(from: speech) else { return nil }
        let bad = ["还是", "或者", "是不是", "要不要", "什么", "怎么", "你们", "我们", "他们", "这个", "那个", "自己", "咱们"]
        guard !bad.contains(where: { kw.contains($0) }) else { return nil }
        return kw
    }

    /// 识别台词/动作里出现过的场景道具，让引导词的「动作描述」贴合当下画面
    private static func prop(in text: String) -> String? {
        let props = ["密信", "信", "茶", "灯", "烛", "雨", "伞", "披风", "大氅", "刀", "剑", "鞘",
                     "糖", "算盘", "账本", "书", "酒", "窗", "星", "棋", "粥", "汤", "水囊", "书包",
                     "瓜子", "栗子", "帕子", "玉佩", "卷宗", "折", "笔", "琴"]
        return props.first { text.contains($0) }
    }

    private static func classify(speech: String, action: String) -> Context {
        let s = speech + action
        if s.contains("？") || s.contains("?") || s.contains("吗") || s.contains("还是") || s.contains("选") {
            return .asking
        }
        if s.contains("难过") || s.contains("哭") || s.contains("累") || s.contains("怕") || s.contains("委屈") || s.contains("喝") || s.contains("暖") || s.contains("披") || s.contains("糖") || s.contains("烫") || s.contains("凉") {
            return .caring
        }
        if s.contains("胡说") || s.contains("少来") || s.contains("嘴甜") || s.contains("嫌") || s.contains("夸") || s.contains("哼") || s.contains("逗") || s.contains("油嘴") {
            return .teasing
        }
        if s.contains("走") || s.contains("来") || s.contains("坐") || s.contains("陪") || s.contains("说吧") || s.contains("讲") || s.contains("吃") {
            return .inviting
        }
        return .neutral
    }

    /// 语境 → 倾向偏置概率
    private static func bias(of context: Context, for tendency: Suggestion.Tendency) -> Double {
        switch context {
        case .asking:
            return tendency == .comply || tendency == .probe ? 0.85 : 0.3
        case .caring:
            return tendency == .comply || tendency == .act ? 0.8 : 0.35
        case .teasing:
            return tendency == .pull || tendency == .probe ? 0.85 : 0.3
        case .inviting:
            return tendency == .comply || tendency == .act ? 0.8 : 0.35
        case .neutral:
            return 0.5
        }
    }

    private static func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1) < probability
    }

    // MARK: 模板池

    private enum Style { case ancient, campus }

    private struct Pools {
        let comply: [String]
        let probe: [String]
        let pull: [String]
        let act: [String]
    }

    private static func pools(_ style: Style) -> Pools {
        switch style {
        case .ancient:
            return Pools(
                comply: [
                    "（微微低头，声音放轻）好，都依你。",
                    "（认真点头）嗯，我记下了，照你说的办。",
                    "（接过{prop}，指尖收紧了些）……那便听你的。",
                    "（依言坐下，抬眼）「{kw}」是吧。我应了。"
                ],
                probe: [
                    "（抬眼看向你）你这是在夸我，还是在嫌我多事？",
                    "（指了指{prop}）「{kw}」……这话是什么意思？你先说清楚。",
                    "（故作随意地拨了下{prop}）那我换个问法——你希望我答哪个？",
                    "（盯着你看了片刻，忽然轻声）你说这话时，可有一句是真的？"
                ],
                pull: [
                    "（轻笑一声，偏过头）你嘴上这么说，方才那动作倒是诚实。",
                    "（故意把{prop}往回收了收）想要？那你先哄哄我。",
                    "（眼波一转，慢条斯理）哼，方才凶我的气，还没消呢。",
                    "（慢慢凑近半寸，又停住）现在改口，还来得及吗？"
                ],
                act: [
                    "（伸手把{prop}轻轻推向你，直视你）先回我刚才那句话。",
                    "（起身走到你身侧，与你望向同一处）……我陪你想一会儿。",
                    "（替你把{prop}摆正，指腹在边缘敲了敲）嗯，我听着。接着说。",
                    "（安静地把{prop}收好，抬眼）下一句，换你说了。"
                ]
            )
        case .campus:
            return Pools(
                comply: [
                    "（用力点头）好！包在我身上！",
                    "（双手接过{prop}）嗯嗯，听你的！",
                    "（认真在小本本上记下）「{kw}」对吧，记好了哦！"
                ],
                probe: [
                    "（歪着头）咦——这是在夸我，还是在损我呀？",
                    "（眨眨眼）欸那你先说，你希望我选哪个嘛？",
                    "（凑近盯着你看）「{kw}」？……你老实说，是不是有事瞒着我？"
                ],
                pull: [
                    "（鼓起腮帮）哼，这次先原谅你，下不为例！",
                    "（把{prop}抱紧，偷偷瞄你一眼）……真的假的？不许骗我哦。",
                    "（故意看别处，嘴角却憋不住）谁、谁要理你呀……"
                ],
                act: [
                    "（从书包里摸出一颗糖递过去）先吃颗糖，慢慢跟我说！",
                    "（把{prop}往你那边推了推）呐——换你讲了，我听着呢！",
                    "（凑近压低声音）嘘——我给你占好位置了，快说！"
                ]
            )
        }
    }
}
