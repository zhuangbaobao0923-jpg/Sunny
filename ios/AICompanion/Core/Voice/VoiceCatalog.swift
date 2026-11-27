import Foundation

// MARK: - 音色总表（唯一数据源）
//
// 创建角色页的可选音色、聊天语音条、通话，三处都从这里取，
// 避免「页面显示一套、实际调用另一套」。
// 名单与 docs/voice-cast.json 保持一致，改动请两边同步。

struct VoiceOption: Identifiable, Sendable, Equatable {
    let name: String
    let gender: String          // "女" / "男" / "儿童"
    let desc: String
    let voiceID: String
    let speed: Double
    let kind: VoiceKind         // 没有 Key 时回退旧引擎用的近似音色

    var id: String { name }

    init(
        _ name: String,
        _ gender: String,
        _ desc: String,
        _ voiceID: String,
        speed: Double = 1.0,
        kind: VoiceKind
    ) {
        self.name = name
        self.gender = gender
        self.desc = desc
        self.voiceID = voiceID
        self.speed = speed
        self.kind = kind
    }
}

enum VoiceCatalog {
    static let all: [VoiceOption] = [
        // ---- 少女 / 女声 ----
        VoiceOption("大肥鱼·偶像版", "女", "明亮轻盈，带一点气声，成年女性", "voc_rn489h83rcvs", kind: .warmFemale),
        VoiceOption("大肥鱼·迷糊版", "女", "清亮柔软，略带奶气，憨憨的少女", "voc_8yud7hz7c9q2", kind: .softGirl),
        VoiceOption("大肥鱼·机灵版", "女", "清亮甜软，反应轻快，俏皮", "voc_u3nxkd5578wc", kind: .livelyGirl),
        VoiceOption("灵动汐语", "女", "清脆灵动，公主郡主的娇与傲", "voc_tzneby749yja", kind: .livelyGirl),

        // ---- 成年女声 ----
        VoiceOption("冷面铁捕", "女", "中低音、字字利落，女将军与冷面师姐", "voc_4fcdc882gyps", speed: 0.95, kind: .elegantFemale),
        VoiceOption("凤仪（皇后）", "女", "醇厚温润，母仪天下的威严与包容", "voc_psyuun5rky74", kind: .elegantFemale),
        VoiceOption("幽兰影", "女", "甜里带钩，笑里藏刀，宠妃气", "voc_dcccp6b9p466", kind: .softGirl),
        VoiceOption("冷峻调查官", "女", "冷冽压低，不怒自威，女帝气场", "voc_4xhyh9d63huc", kind: .elegantFemale),
        VoiceOption("青史执笔人", "女", "清冷宫廷腔，落难郡主的旧日贵气", "voc_3nw7zw44cxek", kind: .elegantFemale),
        VoiceOption("邻家暖心", "女", "温婉清甜，没有攻击性，邻家妹妹", "voc_p36dbdewwvae", kind: .warmFemale),

        // ---- 男声 ----
        VoiceOption("幽巷引路人", "男", "低沉克制，深夜电台，有城府", "voc_gbaz4j9uyq97", kind: .deepMale),
        VoiceOption("深海低语者", "男", "气声压迫，危险感最强的低音炮", "voc_mtb2gb2f565z", kind: .magneticMale),
        VoiceOption("铁血教头", "男", "硬朗威严，军旅气，像在下命令", "voc_mvdhh8xj9e7k", kind: .deepMale),
        VoiceOption("醇厚匠心师", "男", "温柔年上，醇厚耐听，像在跟你说话", "voc_aa4s73p25jt2", kind: .broadcastMale),
        VoiceOption("星舰指挥官", "男", "沉稳有威严，做决定的人，不油", "voc_q8d8a99gxa7f", kind: .broadcastMale),
        VoiceOption("幕后独白者", "男", "醇厚话剧腔，像有过去的人", "voc_k7tz43q2yxc2", kind: .broadcastMale),

        // ---- 童声 ----
        VoiceOption("大肥鱼·破晓版", "儿童", "清脆明亮，顽皮，动画童声", "voc_d7fhsuhdaptx", kind: .sweetGirl),
    ]

    private static let index: [String: VoiceOption] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.name, $0) }
    )

    static func option(named name: String?) -> VoiceOption? {
        guard let name else { return nil }
        return index[name]
    }

    static func options(gender: String?) -> [VoiceOption] {
        guard let gender else { return all }
        return all.filter { $0.gender == gender }
    }
}
