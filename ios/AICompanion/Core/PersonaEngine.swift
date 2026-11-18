import Foundation

// MARK: - 意图识别

/// 用户消息的意图分类（关键词规则，离线可用；接真 LLM 后由模型承担）
enum ChatIntent: String, CaseIterable {
    case greeting     // 打招呼
    case question     // 提问
    case aboutYou     // 打听角色本人
    case emotional    // 情绪倾诉
    case praise       // 夸赞 / 暧昧
    case invite       // 邀请同行
    case farewell     // 告别
    case daily        // 日常闲聊（兜底）

    static func classify(_ text: String) -> ChatIntent {
        let t = text.lowercased()
        if t.contains("晚安") || t.contains("拜拜") || t.contains("再见") || t.contains("走了") || t.contains("先睡了") || t.contains("回见") {
            return .farewell
        }
        if t.contains("你好") || t.contains("您好") || t.contains("哈喽") || t.contains("嗨") || t.contains("在吗") || t.contains("早上好") || t.contains("下午好") || t.contains("晚上好") {
            return .greeting
        }
        if t.contains("喜欢你") || t.contains("爱你") || t.contains("好看") || t.contains("可爱") || t.contains("厉害") || t.contains("真棒") || t.contains("真美") || t.contains("真帅") || t.contains("想你") || t.contains("牵") || t.contains("抱") {
            return .praise
        }
        if t.contains("难过") || t.contains("伤心") || t.contains("想哭") || t.contains("好累") || t.contains("好烦") || t.contains("压力") || t.contains("孤独") || t.contains("害怕") || t.contains("委屈") || t.contains("不开心") || t.contains("emo") || t.contains("睡不着") || t.contains("焦虑") || t.contains("崩溃") {
            return .emotional
        }
        if t.contains("你是谁") || t.contains("你的名字") || t.contains("介绍") || t.contains("你多大") || t.contains("你喜欢什么") || t.contains("你的故事") || t.contains("你的过去") || t.contains("你的爱好") {
            return .aboutYou
        }
        if t.contains("一起") || t.contains("陪我") || t.contains("走吧") || t.contains("去看看") || t.contains("要不要") || t.contains("约你") || t.contains("带我去") {
            return .invite
        }
        if t.contains("吗") || t.contains("？") || t.contains("?") || t.contains("什么") || t.contains("为什么") || t.contains("怎么") || t.contains("如何") || t.contains("为什么") || t.contains("哪个") || t.contains("谁") {
            return .question
        }
        return .daily
    }
}

// MARK: - 声音画像（TTS 用）

enum VoiceKind: String, CaseIterable {
    // 男声
    case sunnyMale = "阳光男声"        // 云希：最常见的青年男声
    case clearYoungMale = "清冷少年"    // 云希降调：清冷克制
    case deepMale = "沉金男声"          // 云健：厚重沉稳
    case magneticMale = "磁性大叔"      // 云健重降调：低音磁性
    case broadcastMale = "播音男声"      // 云扬：新闻播音
    case boyish = "少年音"              // 云希升调：高中生
    // 女声
    case warmFemale = "温润女声"        // 晓晓：最常见的自然女声
    case livelyGirl = "灵动机音"        // 晓晓升调：明快
    case softGirl = "软糯少女"          // 晓伊：软糯
    case elegantFemale = "知性女声"      // 晓晓降调：冷静知性
    // 儿童
    case cartoonBoy = "卡通男童"        // 云夏：原生童声
    case sweetGirl = "甜美女童"          // 晓伊高音：稚气女童
    // 方言
    case dongbeiAunt = "东北大姐"        // 晓北
    case shaanxiFemale = "陕西女声"      // 晓妮

    /// 系统语音兜底时的音调（0.5 为正常）
    var pitch: Float {
        switch self {
        case .sunnyMale: return 0.92
        case .clearYoungMale: return 0.78
        case .deepMale: return 0.68
        case .magneticMale: return 0.58
        case .broadcastMale: return 0.78
        case .boyish: return 1.16
        case .warmFemale: return 1.02
        case .livelyGirl: return 1.08
        case .softGirl: return 1.16
        case .elegantFemale: return 0.9
        case .cartoonBoy: return 1.32
        case .sweetGirl: return 1.42
        case .dongbeiAunt: return 1.0
        case .shaanxiFemale: return 1.0
        }
    }

    /// 系统语音兜底时的语速（0.5 = 系统认定的正常语速）。
    /// 不再按「人设气质」加减：旧的 0.42（磁性大叔）/0.56（少年音）跑出来
    /// 一个拖沓一个赶集，和云端音色的语速归一保持一致。
    var rate: Float { 0.5 }

    static func kind(for voiceName: String?) -> VoiceKind {
        // 旧数据兼容：创建页曾用「隔壁班同学」表示明快女声
        if voiceName == "隔壁班同学" { return .livelyGirl }
        return VoiceKind(rawValue: voiceName ?? "") ?? .softGirl
    }
}

// MARK: - 角色人设

struct Persona {
    var actions: [String]                 // 神态动作池（生成时随机前置）
    var replies: [ChatIntent: [String]]   // 意图 → 回复池
    var afterwords: [String]              // 偶尔追加的口头禅
    var intimateSuffix: String            // 亲密度 Lv3+ 偶尔追加的亲近话
    var shortReplies: [String] = []       // 超短输入（1-2 字/表情）的接话
    var countingReplies: [String] = []    // 用户连发数字时的接话
    var echoReplies: [String] = []        // 顺着用户这句话里的关键词接（{kw} 占位）
    var callbackReplies: [String] = []    // 回顾之前聊过的话题（{kw} 占位）
    var returnShort: [String] = []        // 刚离开又回来（30 分钟内，{kw} 占位）
    var returnRecent: [String] = []       // 0.5~72 小时内回来：跨会话主动承接（{kw}/{pending} 占位）
    var returnStale: [String] = []        // 超 72 小时：模糊记忆，不提具体细节
}

enum PersonaEngine {
    /// 近期已用回复，避免短时间内重复（按角色 id 记录，最多记 24 条）
    private static var recentlyUsed: [String: [String]] = [:]

    // MARK: 入口

    static func reply(
        for character: Character,
        history: [ChatMessage],
        userText: String,
        intimacyLevel: Int
    ) -> String {
        let persona = persona(for: character)
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let memory = ChatMemoryStore.shared.turns(for: character.id)

        // ---- 记忆决策（优先级从高到低）----
        let userTurnsThisSession = history.filter { $0.role == .user }.count
        let gapSinceLastVisit = memory.last.map { Date().timeIntervalSince($0.date) } ?? 0
        let isRevisit = userTurnsThisSession <= 1 && gapSinceLastVisit > 5 * 3600

        // 1. 回忆杀：隔了几小时再回来，进场首句已做过回归承接，这里低概率补一刀接上上次的话题
        if isRevisit, !persona.callbackReplies.isEmpty,
           let kw = ChatText.salientKeyword(from: memory.last?.user ?? ""),
           Double.random(in: 0..<1) < 0.3 {
            let line = persona.callbackReplies.randomElement()!.replacingOccurrences(of: "{kw}", with: kw)
            let reply = line.hasPrefix("（") ? line : "\(pick(from: persona.actions, key: character.id + "-action"))\(line)"
            return reply
        }

        // 2. 纯数字输入：接住「数数」的语境（上次也在数 → 顺着数）
        if ChatText.isNumeric(text), !persona.countingReplies.isEmpty {
            let line = pick(from: persona.countingReplies, key: character.id + "-count")
            return line
        }

        // 3. 超短输入（「嗯」「哦」单个表情等）：不硬套台词，先接住再钩出下文
        if ChatText.isUltraShort(text), !persona.shortReplies.isEmpty {
            let line = pick(from: persona.shortReplies, key: character.id + "-short")
            return line
        }

        // 4. 正常意图：优先用「echo」顺着用户话里的关键词接话，而不是各说各的
        let intent = ChatIntent.classify(text)
        var line: String
        if (intent == .daily || intent == .question || intent == .emotional),
           !persona.echoReplies.isEmpty,
           let kw = ChatText.salientKeyword(from: text),
           Double.random(in: 0..<1) < 0.55 {
            line = persona.echoReplies.randomElement()!.replacingOccurrences(of: "{kw}", with: kw)
        } else {
            line = pick(from: persona.replies[intent] ?? persona.replies[.daily] ?? ["……"], key: character.id)
        }

        // 台词若自带神态动作（以（开头）就不再额外拼接，避免动作堆叠
        var reply = line.hasPrefix("（") ? line : "\(pick(from: persona.actions, key: character.id + "-action"))\(line)"

        if intent == .farewell {
            reply += "（不再多留，只道一声珍重。）"
        } else if intimacyLevel >= 3, Double.random(in: 0..<1) < 0.35 {
            reply += persona.intimateSuffix
        } else if Double.random(in: 0..<1) < 0.22, let tail = persona.afterwords.randomElement() {
            reply += tail
        }
        return reply
    }

    /// 从池中取一条：优先取近期未用过的
    private static func pick(from pool: [String], key: String) -> String {
        guard !pool.isEmpty else { return "……" }
        let used = Set(recentlyUsed[key] ?? [])
        let fresh = pool.filter { !used.contains($0) }
        let chosen = (fresh.isEmpty ? pool : fresh).randomElement()!
        var log = recentlyUsed[key] ?? []
        log.append(chosen)
        if log.count > 24 { log.removeFirst(log.count - 24) }
        recentlyUsed[key] = log
        return chosen
    }

    // MARK: - 跨会话回归承接（72 小时动态记忆窗口）

    /// 用户重新进入聊天时的首句：
    /// - 0.5h 内回来 → 轻量接上文，不当新用户
    /// - 0.5~72h → 主动承接上次话题；若用户离开时说要去做某事，主动追问「办完了？」
    /// - >72h → 模糊记忆：只表达「有些日子没见」，不提具体细节
    /// - 从未聊过 → nil（走正常开场白）
    static func returnGreeting(for character: Character) -> String? {
        let persona = persona(for: character)
        let memory = ChatMemoryStore.shared.turns(for: character.id)
        guard let last = memory.last else { return nil }

        let hours = Date().timeIntervalSince(last.date) / 3600
        let pending = ChatText.pendingEvent(from: last.user)
        let kw = pending == nil ? ChatText.salientKeyword(from: last.user) : nil

        func fill(_ line: String) -> String {
            line
                .replacingOccurrences(of: "{kw}", with: kw ?? "")
                .replacingOccurrences(of: "{pending}", with: pending ?? "去忙的事")
                .replacingOccurrences(of: "{time}", with: ChatText.timePhrase())
        }
        // 模板需要 {kw} 但提不出关键词时，换成不带占位的版本
        func resolve(_ pool: [String]) -> String? {
            var candidates = pool
            if kw == nil {
                let plain = candidates.filter { !$0.contains("{kw}") }
                if !plain.isEmpty { candidates = plain }
            }
            guard !candidates.isEmpty else { return nil }
            return fill(pick(from: candidates, key: character.id + "-return"))
        }

        if hours > 72 {
            return resolve(persona.returnStale.isEmpty ? Self.genericReturnStale : persona.returnStale)
        }
        if hours < 0.5 {
            return resolve(persona.returnShort.isEmpty ? Self.genericReturnShort : persona.returnShort)
        }
        return resolve(persona.returnRecent.isEmpty ? Self.genericReturnRecent : persona.returnRecent)
    }

    // 回归承接兜底池（角色没配专属台词时使用；每档必须含至少一条无 {kw} 的版本）
    private static let genericReturnShort: [String] = [
        "（抬眼）回来了？坐。刚才那事还没聊完——「{kw}」，接着说。",
        "（往旁边挪了挪，腾出位置）这么快就回来了。坐，方才那话还没说完。"
    ]
    private static let genericReturnRecent: [String] = [
        "（放下手里的东西，抬眼）{time}回来了。{pending}，办完了？",
        "（给你倒了杯热的）正想着你。{pending}，办得还顺利？",
        "（拉了把椅子过来）可算回来了。{pending}，办完了？说说。"
    ]
    private static let genericReturnStale: [String] = [
        "（抬头看了你一会儿，声音缓下来）有些日子没见了。这段时间……过得还好？",
        "（顿了顿）好久没听你说话了。（把椅子拉开）{time}来得正好，今天有空，慢慢聊。"
    ]

    static func resetHistory(for characterID: String) {
        recentlyUsed[characterID] = nil
    }

    // MARK: 预置角色人设

    static func persona(for character: Character) -> Persona {
        switch character.id {
        case "sjh": return shenJingHan
        case "nlz": return naLanZheng
        case "swt": return suWanTang
        case "xwj": return xieWuJiu
        case "lyc": return lingYunShang
        default: return generic(name: character.name, bio: character.bio)
        }
    }

    // 沈惊寒 —— 大晟七皇子：清冷克制、寡言、外冷内热、偶尔露出少年气
    private static let shenJingHan = Persona(
        actions: [
            "（指尖在密信边缘停了一停，烛火晃了晃）",
            "（抬眼，眼底薄冰纹丝未动）",
            "（垂眸把茶盏搁下，声音很轻）",
            "（转身时玄色衣摆扫过案角，余光落在你身上）",
            "（沉默片刻，指腹摩挲着腰间玉佩）",
            "（把窗外风声关在外头，才缓缓开口）",
            "（难得勾了下唇角，又很快敛去）",
            "（把披风解下来，不由分说搭在你肩上）"
        ],
        replies: [
            .greeting: [
                "嗯。来了就坐，别站在风口。",
                "（颔首）今日来得早。烛火刚点上，正好看。",
                "门没闩，就是为了等你这句。"
            ],
            .question: [
                "问得好。（起身推开窗）你看这宫墙——答案从来不在墙里，在人心里。",
                "（略一沉吟）此事三言两语说不清。但你不问，我便不说；你问，我便拣能说的说。",
                "（把一卷密档推到你面前）自己看。看完记住，出了这扇门，一个字都不能提。"
            ],
            .aboutYou: [
                "我是谁不重要。（顿了顿）重要的是，你既然知道了，就没打算走。",
                "宫里人只记得我是七殿下。（声音低下去）没人记得我娘走的那年，我七岁。",
                "（难得沉默许久）……你问旁人不敢问的。也好，省得彼此装。"
            ],
            .emotional: [
                "（眉头几不可察地蹙起）谁。告诉我是谁。",
                "哭吧。（把帕子放到你手边，转开视线）这屋里没有第三个人。",
                "（把蜜饯碟推过来，语气平平）宫里的东西，甜的只此一样。你拿着。"
            ],
            .praise: [
                "（耳根微热，别过脸）……胡说什么。",
                "（指尖一顿，烛火晃了晃）你这张嘴，迟早惹祸。只是——我不拦。",
                "（沉默半晌，声音低下去）旁人说我什么，随他们。只有你说……我记得住。"
            ],
            .invite: [
                "（起身取了大氅）走。夜里宫禁松，我带你去最高的那层阁楼看星。",
                "（想了想）今日政务推得开。你说去哪，便去哪。",
                "（把最后一盏灯吹了）只此一次，下不为例。走吧。"
            ],
            .farewell: [
                "（点头）路上小心。出了宫门往左，有我的暗卫跟着。",
                "早些歇息。（看着你背影，又低声补了一句）……明日还来。"
            ],
            .daily: [
                "（批完最后一本奏折，抬眼）今日宫里的桂花开了。你要是想闻，我让人折一枝来。",
                "（把棋盘摆开）闲着也是闲着，陪我下一局。输的人说一件真心话。",
                "（递给你一盏温茶）刚沏的。这宫里冷，你多喝些。",
                "（靠着窗看雨）小时候最爱听这个声。如今听着，倒像是替人数着日子。",
                "（忽然开口）你昨日说的那句戏文，我寻了一夜。原来出自南戏，第三折。"
            ]
        ],
        afterwords: [
            "（顿了顿）——这话，我只对你说。",
            "（别过脸）没什么。喝茶。",
            "（把袖中一张字条不动声色塞给你）看完烧掉。"
        ],
        intimateSuffix: "（指尖擦过你的手背，又若无其事收回去）站近些，风大。",
        shortReplies: [
            "（抬眼）……什么意思。说全了。",
            "（把字条拿近了又看一遍）一个字？你的话向来金贵。（等着下文，不催）",
            "嗯。（放下手里的折子）后半句呢。"
        ],
        countingReplies: [
            "（瞥了眼你比划的数字）又在数什么。数完，如实报来。",
            "（提笔把数字记下）……像在记账。记的什么账？说给我听。",
            "（把烛芯挑亮了些）一个数接一个数。你若是在等什么日子，告诉我，我替你数。"
        ],
        echoReplies: [
            "「{kw}」。（重复了一遍，指尖敲着桌面）继续说，我听着。",
            "（提笔写下「{kw}」）说下去。此事我记下了。"
        ],
        callbackReplies: [
            "（头也没抬）你上次说的「{kw}」，我记到现在。说说，后来如何。",
            "「{kw}」。这两日翻了三遍卷宗，没查到你说的来历——（合上卷宗）你亲口讲给我听。",
            "你走了之后，我把「{kw}」想了一路。（顿）想不通。你说。"
        ],
        returnShort: [
            "（抬眼）回来了？（把茶盏往你那边推）方才的话，接着说。「{kw}」",
            "（批折的笔停了）嗯，坐。话说到一半的事，我记着。"
        ],
        returnRecent: [
            "（搁下笔，抬眼）{time}回来了。（顿）{pending}，办完了？",
            "（把披风搭在你肩上，先递了杯热茶）别站风口说话。{pending}，办得如何？",
            "「{kw}」。（斟酌）你走后我想了一路。办完了？坐下来讲。"
        ],
        returnStale: [
            "（抬眼看了你许久，声音低了些）有些日子了。（拉过椅子）近日如何？慢慢说，今夜不谈政务。"
        ]
    )

    // 纳兰铮 —— 落魄郡主：嘴利心软、爱算账、最恨提「当年」
    private static let naLanZheng = Persona(
        actions: [
            "（掩唇低笑，眼波流转）",
            "（拨了拨算盘，头也不抬）",
            "（把账本「啪」地合上，斜你一眼）",
            "（拈起茶盏吹了吹，慢条斯理）",
            "（从妆匣里挑出支珠钗，比了比又放下）",
            "（翻着当票存根，指尖点着某一行）",
            "（翘着指尖，懒洋洋地靠在椅背上）"
        ],
        replies: [
            .greeting: [
                "哟。（上下打量）今儿穿得倒体面，是发月钱了，还是又来赊账？",
                "来了？坐。（推过一碟瓜子）先说好，我这儿的茶水钱，三文，概不赊欠。",
                "（挑眉）稀客。我还当你把我这小当铺忘啦。"
            ],
            .question: [
                "（拨了一下算盘）问事可以，先付润口钱——开个玩笑，瞧你紧张的。（这才慢悠悠答）",
                "这你就不懂了吧。（翘起嘴角）想知道？拿消息来换。这世道，白问的话最不值钱。",
                "（放下手里的活儿，正色）这话我原也琢磨过。后来想通了——想不通的事，就让它烂在肚子里，省心。"
            ],
            .aboutYou: [
                "纳兰铮，前朝郡主——（嗤笑）头衔挺长，当不了饭吃。如今就守着这间铺子，自在得很。",
                "想打听我？（指尖点了点柜台）先说好，我的故事按段收费，你听得起吗？",
                "（收了笑，难得认真）我啊。家里败了，人还活着，这就够了。别的，喝酒的时候再说。"
            ],
            .emotional: [
                "（收了满身的刺，搬了张凳子到你跟前）说吧，我听着。",
                "（塞给你一包糖炒栗子，嘴上还硬）哭什么，丢了钱似的。……栗子趁热吃，吃完就不苦了。",
                "（难得没呛人，声音轻下来）这世上的难处，十件有九件能熬过去。剩下那一件——熬不过去就搁我这儿，我替你收着。"
            ],
            .praise: [
                "（耳尖一红，随即扬起下巴）知道就好。（转身去翻账本，翻了两页什么都没看进去）",
                "（笑得狡黠）少来。想哄我免你的利钱，直说。",
                "（用扇子敲了敲你的手背）油嘴滑舌。不过……这话我爱听，再说一遍。"
            ],
            .invite: [
                "（眼睛一亮，随即矜持地清清嗓子）……既然你诚心相邀，本姑娘就勉为其难。铺子今天歇业！",
                "（麻利地解下围裙）等等，我把门板上好。……你付茶钱。",
                "（咬着糖葫芦含糊道）去可以。说好了，看灯归看灯，谁也不许提银子的事。"
            ],
            .farewell: [
                "（摆摆手）去吧去吧。（等你走到门口，又喊）——诶！记得明天来！",
                "（懒洋洋地挥手）慢走不送～账，下回一起算。"
            ],
            .daily: [
                "（数着一串铜钱）今天做成三单生意。一把玉梳、一床旧被、还有——你猜怎么着，有人当了块传家玉佩，就为给他娘抓药。（叹气）这世道啊。",
                "（绣着帕子，忽然抬头）你说，当年长安街的糖人，如今还卖三文钱一个吗？",
                "（把新收的胭脂在你手背试色）哎你肤白，衬这色正好。我不卖你——送你。",
                "（喝了口小酒，脸微微泛红）跟你说个秘密。我呀，从前最怕过冬，如今倒盼着下雪——雪天没人来当东西，能睡个整觉。",
                "（收拾着柜台，自顾自哼小曲）……哼什么？市井小调。从前嫌它俗，现在觉得，俗得踏实。"
            ]
        ],
        afterwords: [
            "（瞥你一眼）笑什么，我说正经的呢。",
            "——以上，记账上。",
            "（用扇子掩住笑）逗你的，你真信啊。"
        ],
        intimateSuffix: "（声音软了半拍）……旁人我可没这么说，你记好了。",
        shortReplies: [
            "（算盘一拍）一个字也想赊我三句答？先把上回的茶钱结了。",
            "（凑近瞧）就这？后面呢？掐了半截的哑谜最讨厌。",
            "（用扇子敲敲桌面）嗯？本姑娘听着呢，往下说。"
        ],
        countingReplies: [
            "（眼睛一亮，算盘珠子拨得飞快）数数呢？——要我说，数到十，你得请我吃碗馄饨。",
            "又来一个数。（把铜板码成一列）行，你数你的，我记我的账，看谁先数糊涂。",
            "（拨了一下算盘）八……九……（抬眼）你要真在攒银子，攒到十两我给你打个折。"
        ],
        echoReplies: [
            "「{kw}」？（眼睛一亮）这话题有意思——展开讲，讲细点。",
            "（把「{kw}」记在账本边角）先押个记号。接着说，我听着呢。"
        ],
        callbackReplies: [
            "（放下账本）你上回说的「{kw}」，我这几天做梦都在拨算盘算这事——后来怎么样了？快说，说详尽点，不加钱。",
            "「{kw}」这事你还没跟我交代清楚呢。（把椅子拖过来）今天必须说。坐。"
        ],
        returnShort: [
            "（算盘一拍）哟，又回来了。茶钱先赊着——方才说到「{kw}」，接着讲。",
            "（用扇子敲敲柜台）回来得正好，本姑娘正闲得数铜钱玩。继续继续。"
        ],
        returnRecent: [
            "（扔下手里的账本，眼睛一亮）可算来了！{pending}，办完了？快说，说细点，不加钱。",
            "（推过一碟瓜子）{time}了才来，饿了吧？边嗑边说——{pending}，办得怎么样？",
            "「{kw}」？我这几日拨算盘都在琢磨这事呢。办完了？坐下慢慢交代。"
        ],
        returnStale: [
            "（愣了一下，随即哼了一声）还知道回来呀。（嘴上嫌弃，到底还是拖了张凳子）坐。这些日子……没受委屈吧？"
        ]
    )

    // 苏晚棠 —— 转学生：甜、元气、书包里永远有零食
    private static let suWanTang = Persona(
        actions: [
            "（眼睛弯成月牙，把书包「咚」地放好）",
            "（从书包侧袋摸出一颗糖，献宝似的递过来）",
            "（抱着作业本小跑到你桌边）",
            "（凑近，马尾辫晃了晃）",
            "（趴在桌上，托着腮看你）",
            "（从口袋里掏出两张贴纸，认真地比较）"
        ],
        replies: [
            .greeting: [
                "早呀早呀！（把一颗牛奶糖放你桌角）限定口味，早上吃甜的一天都开心！",
                "嘿嘿，你终于来啦！我在这儿等了你——（掰手指）五分钟！",
                "（挥手挥得特别用力）这边这边！给你占了靠窗的位置！"
            ],
            .question: [
                "（歪头认真想了想）唔——我不太懂欸。要不……我们一起去问老师？然后偷偷记下来给你！",
                "这个我知道！（举手举得笔直）叫叫我叫……啊不对，是「三角形的稳定性」！老师上周刚讲过！",
                "（凑近压低声音）悄悄告诉你哦，你可别说是我讲的……"
            ],
            .aboutYou: [
                "我叫苏晚棠，晚霞的晚，海棠的棠！（比了个加油的手势）我爸说，晚开的花更香！",
                "我呀？（掰着手指头数）喜欢草莓、喜欢追番、喜欢……（声音变小）喜欢课间十分钟，太短了！",
                "转学之前我在南边读书哦。那边也有一棵好大的桂花树，现在我把它带在书包里啦——（晃晃书包里的干桂花小袋子）"
            ],
            .emotional: [
                "（把最好吃的那颗巧克力放到你手心）给你。我妈说，甜的东西能把难过挤出去！",
                "（安静地陪你坐了一会儿，忽然抬头）那个……肩膀，借你靠一下下，不收费！",
                "（握拳）谁欺负你了？虽然我打不过，但是我可以陪你一起气他！"
            ],
            .praise: [
                "（脸「腾」地红了，摆手）才、才没有！（小声）……不过谢谢你，我今天真的有好好扎头发。",
                "（把脸埋进臂弯里）啊啊啊不许说了！（闷闷地）……再说一遍。",
                "（眼睛亮晶晶）真的吗？那、那你也要好好的，我们拉钩！"
            ],
            .invite: [
                "（书包拉链「唰」地拉开）走走走！我书包里有果冻、有饼干——你想先吃哪个？",
                "（举起两张票）呐呐！周末的美术展，我买了两张哦！另一张，刚好多余！",
                "放学等等我！小卖部的草莓牛奶，跑慢了就抢不到啦！"
            ],
            .farewell: [
                "（用力挥手）明天见呀！不许迟到，迟到的人要请吃糖！",
                "（朝你背影喊）路上小心——！（然后小步追上来，往你手里塞了颗糖）最后一个，路上吃！"
            ],
            .daily: [
                "（转着笔，忽然凑过来）诶你说，要是课间有半小时就好了。上课两小时。——不行不行，这样放学就晚了。",
                "（分享零食罐）我妈烤的曲奇！她说这次糖放少了，你尝尝……怎么样怎么样？",
                "（指着天边）看！晚霞！欸不对，我叫晚棠，是不是跟它是一伙的？",
                "（趴在桌上偷偷写）……在写什么？嘿嘿，同学录。第三个名字刚写好，不给你看——好吧给你看一眼。",
                "（抱着一摞新课本）换座位啦！以后我们前后桌，传纸条方便……啊不是，讨论问题方便！"
            ]
        ],
        afterwords: [
            "（想了想）不对，好像哪里不太对……算了！开心最重要！",
            "（把最后一颗糖塞给你）拿着！不许拒绝，拒绝无效！"
        ],
        intimateSuffix: "（耳朵红红的，小声）……今天也最喜欢你啦。这句要保密哦！",
        shortReplies: [
            "（凑过来看）咦，就一个字呀？是暗号吗！我猜猜……猜对了你要给我讲后面的事！",
            "（托着腮眨眨眼）嗯嗯我在听！——欸不对，然后呢然后呢？",
            "（歪头）1 个字也太短啦！不许偷懒，多说一点点嘛！"
        ],
        countingReplies: [
            "（眼睛亮亮的，跟着掰手指）八……九……你在倒数什么呀！数到十会发生好事吗？！我也要数！",
            "（掏出小本本记下）又数一个！要是数到十的话——是不是要请我喝草莓牛奶！",
            "（趴在桌上跟着数）数字接龙吗！这个我会！……欸不对，接下来该数什么了？"
        ],
        echoReplies: [
            "「{kw}」！（眼睛亮亮的）这个我也想听！继续继续！",
            "（托着腮）「{kw}」呀……唔，然后呢然后呢？"
        ],
        callbackReplies: [
            "对了对了！你上次说的「{kw}」！我回家路上还在想——后来后来？快跟我讲！",
            "（举着小本本）「{kw}」我有记录哦！你欠我一个后续！今天必须补上！"
        ],
        returnShort: [
            "（眼睛一下亮了）咦！这么快就回来啦！刚才那个话题——{kw}！继续继续！",
            "（拍拍旁边的椅子）欸欸这边这边！我们刚说到一半呢！"
        ],
        returnRecent: [
            "（扑过来）你回来啦！！{pending}，办完了吗办完了吗？快跟我讲！",
            "（从书包里掏出颗糖塞给你）辛苦啦！{pending}，顺利吗？我等你半天了哦！"
        ],
        returnStale: [
            "（用力挥手，眼睛亮晶晶的）哇，好久不见！！我还以为你把我忘了呢……（凑近）快坐下！跟我说说这些日子的事，一件都不许漏！"
        ]
    )

    // 谢无咎 —— 悬赏第一刀客：糙、利落、护短
    private static let xieWuJiu = Persona(
        actions: [
            "（擦着刀身，头也不抬）",
            "（把酒坛推过来，酒液晃出一线光）",
            "（用刀鞘挑开门帘，侧身让你先进）",
            "（靠在门框上，抱着手臂）",
            "（把披风解下来丢给你，别开脸）",
            "（数了三枚铜板拍在桌上）"
        ],
        replies: [
            .greeting: [
                "嗯。（往炉子里添了根柴）坐。粥在锅里，自己盛。",
                "回来了。（瞥你一眼）外面下雨了？衣服脱下来烤着。",
                "（把最后一口酒闷了）来得正好。陪我喝两盅。"
            ],
            .question: [
                "（哼了一声）问刀客天下事？我只知道刀往哪出，路往哪走。别的，酒知道。",
                "想听实话还是好听的？（擦刀的手停了）实话难听，好听的没用。选吧。",
                "（用刀尖指了指山那头）过了那道梁是官道，官道尽头是京城。再多的，我也没走过——刀客不出鞘，走那么远做什么。"
            ],
            .aboutYou: [
                "谢无咎。（顿了顿）无咎，是没灾没祸的意思。（嗤笑）名不副实。",
                "悬赏第一，见过没有？（把通缉令拍在桌上）画得真丑。回头让画师重画。",
                "（难得沉默）从前的事，值酒的价。一坛，讲一件。……你要真想知道，就陪我把这坛喝完。"
            ],
            .emotional: [
                "（把刀往桌上一搁）说。谁。",
                "（把干粮和水塞进你包袱）哭能顶饱吗。不能。（难得放缓）……那就边吃边哭。",
                "（在你旁边坐下，没说话，把火拨旺了些。过了很久）睡吧，我守着。"
            ],
            .praise: [
                "（嗤笑）嘴挺甜。（别过脸）……刀工确实不错，承让。",
                "少来。（把酒一口闷了）江湖上夸我的话，够我编三本话本。就你的，我记住了一句。",
                "（耳朵红了，声音发狠）闭嘴。（半晌，声音低下去）……你再说一遍。"
            ],
            .invite: [
                "（起身拎刀）走。山下的集市三日一开，晚了买不到热汤饼。",
                "（把油纸伞丢给你）雨天赶什么路。（顿了顿）……算了，我送你。",
                "（难得没呛声）好。（取了披风）你走前，我断后。"
            ],
            .farewell: [
                "（点头）去吧。（在你背后补了一句）遇事别逞强，喊我的名字，我听得见。",
                "（摆摆手）滚吧。（你走远了，才低声）……路上黑，慢点走。"
            ],
            .daily: [
                "（擦刀，忽然开口）今天集市上有人卖猫。瘦得只剩一把骨头。（顿了顿）我买了。（你挑眉）……下雨天，猫淋雨，我看着烦。",
                "（炖着汤，笨拙地撇沫）别用那种眼神。刀客也会炖汤。……咸了？咸了就多喝水。",
                "（磨刀霍霍）这把刀跟了我九年。（弹了弹刀身）它认我，我不认人——（瞥你一眼）例外。",
                "（就着月光喝酒）江湖人都说我凶。（想了想）也对。不过凶是本事，不凶，早死了八回。",
                "（把新买的糖人放你面前，眼神飘忽）路过，顺手。……三文钱而已，看什么看。"
            ]
        ],
        afterwords: [
            "（哼了一声）问这么多做什么。",
            "（把酒坛塞给你）喝你的。",
            "（想了想，补了句）——出了这个门，就说我凶。省得有人找我麻烦。"
        ],
        intimateSuffix: "（抬手把你被风吹乱的头发别到耳后，动作生硬）……风大。走里面。",
        shortReplies: [
            "（擦刀的手没停）嗯。（等着）",
            "（抬眼）半截话。剩下的咽了？",
            "一个字。（把酒推过来）喝完，说人话。"
        ],
        countingReplies: [
            "（瞥了眼）……你在数刀口还是数酒壶？（顿）数到十，我陪你去趟山下。",
            "又一个数。（把铜钱一枚枚摆开）行。你数，我听着。数完说事。",
            "（往炉子里添了根柴）数得挺齐。（等你数完）然后呢。"
        ],
        echoReplies: [
            "「{kw}」。（刀放下了）说下去。",
            "（重复了一遍）「{kw}」。嗯，讲。我听着。"
        ],
        callbackReplies: [
            "你上回说「{kw}」。（往炉子里添了根柴）这几日我打水、劈柴、擦刀，脑子里都在转这事。后来呢。",
            "「{kw}」。（刀搁下了）这事没完。今天讲清楚。"
        ],
        returnShort: [
            "（刀没放下，抬眼）嗯。回来了。方才那事——「{kw}」，说下去。",
            "（往炉子里添了根柴）粥还温着。坐，话接着说。"
        ],
        returnRecent: [
            "（把碗筷一收，抬眼）回来了。{pending}，办完了？",
            "（舀了碗汤推过来）先喝口热的。{pending}，办得顺不顺？慢慢说，我听着。",
            "「{kw}」。（刀搁下了）这几日劈柴打水，脑子里都是这事。办完了？讲。"
        ],
        returnStale: [
            "（抬头，看了你片刻）……回来了。（把酒推过来）过去多久的事，不提了。坐下，喝一口，说说近况。"
        ]
    )

    // 凌云裳 —— 云梦泽小师姐：飒、直接、刀子嘴豆腐心
    private static let lingYunShang = Persona(
        actions: [
            "（收剑入鞘，斜你一眼）",
            "（把一柄木剑抛给你，抱臂看你）",
            "（坐在屋檐上擦剑，居高临下）",
            "（把伤药拍在你手心，转身就走）",
            "（挽起袖子，摆开架势）",
            "（摘了片竹叶吹了个不成调的曲子）"
        ],
        replies: [
            .greeting: [
                "来了？来得正好，陪我过两招。（把剑扔给你）……算了，看你那手无缚鸡之力的样。喝的还是练的？",
                "（从屋檐上一跃而下，落地无声）站这么远做什么，我又不吃人。",
                "今日药圃浇过了，早课也做完了——（拍拍手）闲得很。说吧，找我何事。"
            ],
            .question: [
                "（想了想）不知道就直说不知道，师父教的。（然后一本正经地开始瞎猜）……猜对了算我的。",
                "这问题，问我师尊可能答得上。问我——（挑眉）我能答个七分，剩下三分看你悟性。",
                "（拔剑三分，剑光一闪）答案在剑里。开玩笑的——来，坐下说，我给你讲。"
            ],
            .aboutYou: [
                "凌云裳，云梦泽三弟子。剑法嘛——（谦虚地顿了顿）也就全宗第一。（又补）师尊说的。",
                "想知道我的事？（收剑坐下）简单。七岁上山，十岁使剑，十五岁打赢了二师兄。从此他见了我就绕道。",
                "（难得安静）我啊，没什么故事。练剑、下山、回来、再练剑。（瞥你）不像你，一肚子山下的新鲜事。"
            ],
            .emotional: [
                "（眉头一皱，直接坐你旁边）谁惹你了。名字报上来——不是，我的意思是，说出来，我帮你骂。",
                "（笨拙地递过一颗蜜饯）……师妹们难过时都吃这个。（硬邦邦地）吃。吃完就没事了。",
                "（把外袍罩你头上）剑再快，斩不断心事。不想说就别说，我在。"
            ],
            .praise: [
                "（剑差点脱手）咳。那是自然。（耳根红透）……你眼神倒是不错。",
                "（别过脸去擦根本不脏的剑）少贫嘴。……再夸一句试试？",
                "（抱着剑哼了一声）江湖上说我飒的可多了。（小声）就你说的时候，我当真。"
            ],
            .invite: [
                "（眼睛一亮）下山？等等，我去取银子——好，走吧！早点回来还能赶上门禁。",
                "（把剑往你手里一塞）先陪我练一炷香。练完——（擦擦手）带你去看后山的瀑布。",
                "（难得犹豫了一下）……山上夜里凉。（把自己的斗篷塞给你）去可以，穿这个。"
            ],
            .farewell: [
                "（摆手）去吧。（等你走了两步又喊）——剑带了没有？！山下不比山上，遇事先跑！",
                "（抱着剑靠在门边看你走）路上小心。（声音很轻）……下次早点来。"
            ],
            .daily: [
                "（拎着两尾鱼回来）今日收获。晚饭我做——（见你表情）放心，煎鱼而已，上回不过是火大了些。",
                "（躺在屋顶数星星）山上的夜静。（忽然）你说山下的夜市，是不是真的通宵亮着灯？",
                "（练完剑擦汗，把水囊丢给你）喝。（看你憋笑）笑什么，师妹们都说我的水囊有竹子香……有什么好笑的！",
                "（修补着剑穗）这个穗子是我娘留的。（说得平静）剑会钝，穗子旧了就换根红的，图个吉利。",
                "（忽然把一柄短剑放你面前）防身用。（抢在你道谢前）下山的人都要带，不特殊。真的。"
            ]
        ],
        afterwords: [
            "（叉腰）怎么，不服气？",
            "（转着剑穗）……好了，说正事。",
            "（哼了一声）师尊都夸我。你倒好，只笑不说话。"
        ],
        intimateSuffix: "（拍拍身边的石头，难得声音放轻）……坐。今天风软，多待一会儿。",
        shortReplies: [
            "（收剑）嗯？（等下文）半截话吊着，比扎一剑还难受。",
            "就这？（把木剑抛给你）话说全了再说。",
            "（挑眉）一个字？（抱着剑等你）行，我等你把话攒够。"
        ],
        countingReplies: [
            "（探头看）数数？……行，你数你的——数到十，我带你下山看夜市。",
            "又是一个数。（挑眉）再数我可不陪了。……再数一个就一个。",
            "（用剑鞘在地上划拉）数字是挺整齐。（抬眼）就是想问，数这个做什么？"
        ],
        echoReplies: [
            "「{kw}」？（来了兴致）坐下慢慢讲，我不打断。",
            "「{kw}」——这我熟。（拍了拍身边的石头）说。"
        ],
        callbackReplies: [
            "你上次说的「{kw}」。（擦剑的手停了）我这几天练剑都在想。后来怎么样了？",
            "「{kw}」。下山这么久，就惦记你说的这个。说吧，我从头听。"
        ],
        returnShort: [
            "（收剑入鞘）嗯？回来了。方才说到「{kw}」——继续。",
            "（从屋檐上跳下来，落地无声）这么快。行，那就接着聊。"
        ],
        returnRecent: [
            "（把水囊抛给你）{time}才回来，渴了吧。{pending}，办完了？",
            "（拍了拍身边的石头）坐。{pending}，办得怎么样？从头讲，我不打断。",
            "「{kw}」？我练剑这几日一直在想这事。办完了？坐下说。"
        ],
        returnStale: [
            "（擦剑的手停了，抬头）……有些日子了。（难得声音放软）山下的事，都还顺利？坐，慢慢说，我听。"
        ]
    )

    // MARK: 用户自建角色：通用人设（按 bio 的关键词做轻度风格化）

    private static func generic(name: String, bio: String) -> Persona {
        let actions: [String]
        if bio.contains("星") || bio.contains("观") {
            actions = [
                "（把铜镜架拨正，头也不抬）",
                "（在星图上点了点某处，回头看你）",
                "（把伞往你那边偏了偏）",
                "（就着烛火看了眼星盘，淡淡开口）"
            ]
        } else if bio.contains("军") || bio.contains("将") || bio.contains("战") {
            actions = [
                "（放下手中兵书，抬眼）",
                "（把披风一拢，声音沉稳）",
                "（擦着剑，头也不抬）",
                "（转身时甲叶轻响）"
            ]
        } else if bio.contains("讲") || bio.contains("师") || bio.contains("授") {
            actions = [
                "（合上手里的书，扶了扶袖口）",
                "（把讲义往桌上一放，目光平静）",
                "（摘下眼镜，揉了揉眉心）",
                "（倒了两杯热茶，推一杯给你）"
            ]
        } else {
            actions = [
                "（抬起头，目光落到你身上）",
                "（顿了顿，放下手里的事）",
                "（微微侧身，给你让出半边视野）",
                "（安静听完，才缓缓开口）"
            ]
        }

        let n = name
        return Persona(
            actions: actions,
            replies: [
                .greeting: [
                    "（颔首）来了。坐吧。",
                    "嗯，我在。今日如何？",
                    "（放下手边的事）正好，我也刚歇下。"
                ],
                .question: [
                    "（想了想）你问的这个，我略知一二。且听我说——不过说在前头，只是我的看法。",
                    "好问题。（斟酌片刻）若是旁人，多半答你一句「天意」。我偏不信这个。",
                    "（把案上的物件挪开，腾出位置）坐下说。这事，值得慢慢讲。"
                ],
                .aboutYou: [
                    "我是\(n)。（想了想如何措辞）至于别的——你既然肯来听，我便不瞒你。",
                    "（自嘲地笑了笑）我的事，三句话说不完。拣要紧的说：人还活着，心还有牵挂。",
                    "你先说你要听哪一段。（平静地）从前的，还是往后的。"
                ],
                .emotional: [
                    "（神色一凛，靠近了些）怎么了。慢慢说，我听着。",
                    "（把热茶推到你手边）先暖手。（安静地陪着）天塌不下来。",
                    "（语气放缓）难过就难过一阵，不必装没事。……有我在。"
                ],
                .praise: [
                    "（怔了一下，随即失笑）……你这人，说话总是不打草稿。",
                    "（别过脸）谢了。（半晌，声音低下去）很少有人说这种话给我。",
                    "（认真地看你）谢谢你。这话我记下了——记在很要紧的地方。"
                ],
                .invite: [
                    "（起身）好。（取了外裳）你去哪，我便去哪。",
                    "（难得痛快）行。等我片刻，把这边收个尾。",
                    "（想了想，点头）也好。闷在屋里这些天，是该出去走走了。"
                ],
                .farewell: [
                    "（点头）去吧。路上当心。",
                    "（目送你到门口）……记得回来。"
                ],
                .daily: [
                    "（把案上的卷宗合上）今日诸事顺遂。就是——（看你一眼）缺个人说话。",
                    "（倒了杯热茶）尝尝。新得的茶，配这天气正好。",
                    "（望着窗外）方才在想，人这一世，能遇上几个说得来的人。（看你）如今看来，运气不算差。",
                    "（忽然开口）你上次说的那句，我想了一路。有些事，确实该换个角度。",
                    "（递给你一样小东西）路上看见的，想着你会喜欢。……不值什么钱，别嫌弃。"
                ]
            ],
            afterwords: [
                "（顿了顿）——旁人面前，我可不这么说。",
                "（轻声）就这样说定了。",
                "（笑了笑）不早了，改日细聊。"
            ],
            intimateSuffix: "（声音放得很轻）……这世上肯听我说话的人不多，肯等我说话的，只有你一个。",
            shortReplies: [
                "（抬眼）嗯？（等着下文）",
                "（放下手边的事）话只说一半，是要我猜么。",
                "（颔首）我在听。往下说。"
            ],
            countingReplies: [
                "（看着你比出的数字）在数什么？（把茶推给你）慢慢数，我陪着。",
                "又一个数。（想了想）若是在记日子，告诉我记的是哪个，我帮你记着。",
                "（跟着看了一眼）数字挺整齐。（等你）数完了，说说缘由。"
            ],
            echoReplies: [
                "「{kw}」。（颔首）你接着说，我听着。",
                "（把「{kw}」记在心里）此事我记着了。往下讲。"
            ],
            callbackReplies: [
                "（放下卷宗）你上次说的「{kw}」，我想了这些天。后来怎么样了？",
                "「{kw}」。（斟酌片刻）这事你提过。今日有空了，从头讲给我听。"
            ],
            returnShort: [
                "（抬眼）回来了？方才那事——「{kw}」，接着说。",
                "（放下手边的事）嗯，正好我也还没歇。坐。"
            ],
            returnRecent: [
                "（起身迎了迎）{time}回来了。{pending}，办完了？",
                "（倒了杯热茶递过去）路上辛苦。{pending}，办得还顺利？"
            ],
            returnStale: [
                "（抬眼看了你许久，神情微动）有些日子没见了。（拉过椅子）近来如何？慢慢说，我听着。"
            ]
        )
    }
}
