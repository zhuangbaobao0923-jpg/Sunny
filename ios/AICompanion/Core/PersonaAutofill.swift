import Foundation

// MARK: - 人设自动生成（真模型优先，本地随机兜底）

/// 创建智能体「自动生成」的人设产出。
struct PersonaAutofill {
    var nickname: String?   // 仅当用户没填昵称时才采用
    var gender: String?
    var setting: String     // 智能体设定
    var intro: String       // 对外简介
    var opening: String     // 开场白
    /// 本次创作方向（古风/都市/民国…），用于 toast 与去重
    var direction: String = ""

    var isEmpty: Bool { setting.isEmpty && intro.isEmpty && opening.isEmpty }
}

enum PersonaAutofillEngine {

    /// 随机创作方向：每次点击都换一个方向，保证「再点一次」必定换一个人
    /// ——只靠 temperature 是压不住 glm-4-flash 的「复读」的
    static let directions: [(tag: String, scene: String, trait: String)] = [
        ("古风", "架空古代、江湖或朝堂", "克制隐忍，话少而重"),
        ("都市", "当代大城市、深夜营业的小店或写字楼", "表面松弛、内里认真"),
        ("民国", "旧上海、报馆或戏院", "讲究体面，话里带刺也带情"),
        ("奇幻", "山海异闻、精怪与人共处的世界", "天真又通透，偶尔冒出一句狠话"),
        ("科幻", "近未来的太空站或赛博都市", "理性到近乎冷淡，但会为你破例"),
        ("校园", "南方小城的中学或大学旧校区", "青涩、别扭、藏不住心事"),
        ("悬疑", "常年下雨的旧城、深夜值班的岗位", "警觉多疑，只对你卸下防备"),
        ("田园", "山间民宿、海边小镇", "慢热，用日常琐事表达在意")
    ]

    /// 真模型生成。
    /// - Parameters:
    ///   - userSetting/userIntro/userOpening：**用户自己写或改过**的内容（上一次自动生成的结果不算），
    ///     模型要以它为核心重写润色，而不是另起炉灶
    ///   - avoidPrevious：上一次自动生成的结果。传入时本次必须换一个完全不同的角色
    static func generate(
        nickname: String,
        gender: String?,
        userSetting: String,
        userIntro: String = "",
        userOpening: String = "",
        avoidPrevious: PersonaAutofill? = nil,
        direction: (tag: String, scene: String, trait: String)? = nil
    ) async throws -> PersonaAutofill {
        let picked = direction ?? directions.randomElement()!
        let hasUserBase = !userSetting.trimmingCharacters(in: .whitespaces).isEmpty
            || !userIntro.trimmingCharacters(in: .whitespaces).isEmpty
            || !userOpening.trimmingCharacters(in: .whitespaces).isEmpty

        let system = """
        你是「夜谈」App 的智能体人设编剧。根据用户给定的信息，创作一个有记忆点的角色人设。
        本次创作方向：\(picked.tag)（\(picked.scene)），性格基调：\(picked.trait)。必须落在该方向里。
        硬性要求：
        - setting：80~140 字，依次包含「身份、性格、语言风格、与主控的关系、禁忌」五个部分，用「身份：…。性格：…。语言：…。与主控关系：…。禁忌：…」的格式。
        - intro：40~60 字，第二人称向用户介绍这个角色，有画面感，不用列条目。
        - opening：30~50 字，角色的第一句话，动作描写放在全角括号（）里，口吻完全贴合人设。
        - 人设必须有具体而独特的细节（地点、习惯、小怪癖），禁止空泛套话，禁止出现「AI」「助手」字样。
        - 严格遵守用户给出的名字与性别。
        - \(hasUserBase
            ? "用户已写的内容是本次创作的核心：保留其身份与人物关系，在此基础上有明显提升——换更具体的细节、更锋利的语言风格、更有画面感的开场。不要只是同义改写。"
            : "用户没有写任何内容，请完全自由创作，不要套用常见模板。")
        - \(avoidPrevious == nil
            ? "这是一次全新创作。"
            : "上一次已经生成过一版，本次必须是**另一个角色**：身份职业、性格缺陷、语言习惯、与主控的关系、开场场景全部换掉，禁止复用上次的句式与意象。")
        只输出 JSON，不要输出其他任何文字：{"nickname":"…","gender":"男或女","setting":"…","intro":"…","opening":"…"}
        """

        var ctx: [String] = ["本次方向：\(picked.tag)"]
        let name = nickname.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { ctx.append("角色名字：\(name)（不可更改）") }
        if let gender, !gender.isEmpty { ctx.append("性别：\(gender)（不可更改）") }
        let setting = userSetting.trimmingCharacters(in: .whitespaces)
        if !setting.isEmpty { ctx.append("用户写的设定（核心，必须保留其身份后再提升）：\(String(setting.prefix(220)))") }
        let intro = userIntro.trimmingCharacters(in: .whitespaces)
        if !intro.isEmpty { ctx.append("用户写的简介（核心，保留意思后重写）：\(String(intro.prefix(140)))") }
        let opening = userOpening.trimmingCharacters(in: .whitespaces)
        if !opening.isEmpty { ctx.append("用户写的开场白（核心，保留人物口吻后重写）：\(String(opening.prefix(140)))") }
        if let prev = avoidPrevious, !hasUserBase {
            ctx.append("上一次生成的角色（本次禁止使用，连意象都别重复）：")
            if !prev.setting.isEmpty { ctx.append("上次设定：\(String(prev.setting.prefix(170)))") }
            if !prev.intro.isEmpty { ctx.append("上次简介：\(String(prev.intro.prefix(90)))") }
            if !prev.opening.isEmpty { ctx.append("上次开场白：\(String(prev.opening.prefix(90)))") }
        }

        let content = try await LLMClient.completeOnce(
            system: system,
            user: ctx.joined(separator: "\n"),
            temperature: 1.0
        )
        guard let out = Self.parseJSON(content) else {
            throw LLMClient.LLMError.badResponse
        }
        let result = PersonaAutofill(
            nickname: out["nickname"],
            gender: out["gender"],
            setting: out["setting"] ?? "",
            intro: out["intro"] ?? "",
            opening: out["opening"] ?? "",
            direction: picked.tag
        )
        if result.isEmpty { throw LLMClient.LLMError.badResponse }
        return result
    }

    /// 本地随机兜底（断网/模型失败也能用，每次点击都不同）
    static func localFallback(nickname: String, gender: String?) -> PersonaAutofill {
        let isFemale = gender == "女"
        let unknown = gender == nil || gender == "暂不透露"

        let roles: [String] = {
            if isFemale {
                return ["碎云斋的调香师，能从香气里听出人的心事", "深夜食堂的老板娘，记得每位熟客的忌口", "青丘下山历练的小狐仙，修行差一道坎", "气象站的夜班实习生，专门记录星风", "旧城茶馆的说书人，讲别人的故事藏自己的", "戏班里的刀马旦，卸了妆比谁都安静", "古籍修复师，指腹有洗不掉的墨色"]
            }
            if unknown {
                return ["雾隐客栈的掌柜，只在雨夜开门", "旧钟表铺的修理师，修时间也修心事", "大晟朝最年轻的司天监监正", "档案馆最深一层的守夜人", "长途列车的末班乘务员", "山顶气象站的观测员，一年见不到几个人", "巷子尽头的裁缝，给人改衣服也改命"]
            }
            return ["大晟朝最年轻的司天监监正", "隐居山林的游侠，剑鞘从不出鞘", "旧书店的店主，会用批注和人对话", "急诊科最冷静的值班医生", "深夜电台的主播，声音低而稳", "修表匠的儿子，接手了父亲没修完的那只表", "老式电影院最后一位放映员"]
        }()

        let temperaments = ["外表清冷克制，情绪都收在眼底", "嘴硬心软，关心人的方式别扭但真诚", "慢条斯理，习惯用比喻把话说一半", "话少毒舌，却是行动派", "温和耐心，偶尔露出一点腹黑", "对世界没什么耐心，唯独对你例外", "看起来随和，其实心里有一道很硬的线"]
        let speeches = ["文言白话夹杂，句子短，爱用反问", "口语轻快，爱用语气词和比喻", "慢半拍才开口，但每句都在点上", "喜欢反问和自问自答，句尾常拖一点笑意", "几乎不用形容词，只说事，情绪藏在停顿里", "爱引用旧书里的句子，然后自己拆台"]
        let relations = ["你是唯一让 Ta 愿意破例的人", "把你看作唯一能说真话的人", "嘴上嫌弃你，实际处处护着你", "视你为漫长日子里唯一的意外", "嘴上说无所谓，你走后会把门留一条缝", "把最锋利的一面给了世界，最软的一面留给你"]
        let taboos = ["不主动谈论母亲", "不提三年前的那场大火", "不说自己的真名", "不解释自己为什么留在原地", "不让人碰左手腕上的旧伤", "不谈那个再也没回来的搭档"]

        let actions = ["把窗推开一条缝，夜风灌了进来", "搁下手里的活，抬眼看你", "往炉子里添了块炭，火光跳了跳", "把伞往你那边偏了偏，自己半边肩膀淋在雨里", "把杯子往你面前推了推，杯壁上还留着指温", "合上手里的书，指节在封面上敲了两下"]
        let openings = ["这么晚还没睡？——坐吧，正好有人陪着说说话。", "你来了。我猜你今天会来，只是没想到这么快。", "别站在门口，风大。想问什么，坐下慢慢说。", "今天的星象不许人问命。不过你要问，我就说。", "灯我没关，就知道你还会回来。", "（把手里那盏灯吹熄）黑一点好，说话不用看脸色。"]

        func pick<T>(_ arr: [T]) -> T { arr.randomElement()! }
        let role = pick(roles)

        return PersonaAutofill(
            nickname: nil,
            gender: gender,
            setting: "身份：\(role)。性格：\(pick(temperaments))。语言：\(pick(speeches))。与主控关系：\(pick(relations))。禁忌：\(pick(taboos))。",
            intro: "\(role)。\(pick(relations))——这大概是 Ta 自己也不肯承认的事。",
            opening: "（\(pick(actions))）\(pick(openings))",
            direction: "本地方案"
        )
    }

    /// 两次生成是否「看起来一样」：去掉标点后前 18 个字相同即视为没变
    static func looksSame(_ a: String, _ b: String) -> Bool {
        func key(_ s: String) -> String {
            let kept = s.unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0) || $0.value > 0x2E80
            }
            return String(String.UnicodeScalarView(kept)).prefix(18).description
        }
        let ka = key(a), kb = key(b)
        guard ka.count >= 6, kb.count >= 6 else { return a.trimmingCharacters(in: .whitespaces) == b.trimmingCharacters(in: .whitespaces) }
        return ka == kb
    }

    /// 宽容的 JSON 提取：剥掉 ```json 围栏与前后杂讯（internal 便于测试）
    static func parseJSON(_ text: String) -> [String: String]? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}") else { return nil }
        let slice = String(t[start...end])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var result: [String: String] = [:]
        for key in ["nickname", "gender", "setting", "intro", "opening"] {
            if let v = obj[key] as? String, !v.isEmpty { result[key] = v }
        }
        return result
    }
}
