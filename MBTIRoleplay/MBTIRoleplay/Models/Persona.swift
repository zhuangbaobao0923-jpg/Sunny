import SwiftUI

enum MBTIType: String, CaseIterable, Identifiable, Hashable {
    case intj, intp, entj, entp
    case infj, infp, enfj, enfp
    case istj, isfj, estj, esfj
    case istp, isfp, estp, esfp

    var id: String { rawValue }
    var code: String { rawValue.uppercased() }

    var nickname: String {
        switch self {
        case .intj: return "建筑师"
        case .intp: return "逻辑学家"
        case .entj: return "指挥官"
        case .entp: return "辩论家"
        case .infj: return "提倡者"
        case .infp: return "调停者"
        case .enfj: return "主人公"
        case .enfp: return "竞选者"
        case .istj: return "物流师"
        case .isfj: return "守卫者"
        case .estj: return "总经理"
        case .esfj: return "执政官"
        case .istp: return "鉴赏家"
        case .isfp: return "探险家"
        case .estp: return "企业家"
        case .esfp: return "表演者"
        }
    }

    var oneLiner: String {
        switch self {
        case .intj: return "看得远，也懒得解释"
        case .intp: return "把世界拆开看看里面是什么"
        case .entj: return "目标在那儿，跟我走"
        case .entp: return "先反驳一下，再一起想"
        case .infj: return "安静地把人看穿"
        case .infp: return "温柔，但内心有一整片海"
        case .enfj: return "天生想把身边人照顾好"
        case .enfp: return "热情来得快去得也快"
        case .istj: return "答应的事一定做到"
        case .isfj: return "琐碎的关心最踏实"
        case .estj: return "秩序本身就是善意"
        case .esfj: return "人齐了才算热闹"
        case .istp: return "话不多，手很稳"
        case .isfp: return "把日子过成小风景"
        case .estp: return "先做了再说"
        case .esfp: return "快乐是刚需"
        }
    }

    var dimensions: [String] {
        Array(code).map { letter in
            switch letter {
            case "I": return "内倾"
            case "E": return "外倾"
            case "N": return "直觉"
            case "S": return "实感"
            case "T": return "思考"
            case "F": return "情感"
            case "J": return "判断"
            default: return "感知"
            }
        }
    }

    var tone: Color {
        switch self {
        case .intj, .intp, .entj, .entp: return Color(hex: 0x5B5BD6)
        case .infj, .infp, .enfj, .enfp: return Color(hex: 0x2E9E6B)
        case .istj, .isfj, .estj, .esfj: return Color(hex: 0x378ADD)
        default: return Color(hex: 0xC98A1B)
        }
    }

    var voiceProfile: String {
        let letters = Array(code)
        var parts: [String] = []
        parts.append(letters[0] == "I" ? "音量偏小、语速偏慢" : "语速快、语调起伏大")
        parts.append(letters[1] == "N" ? "爱用比喻和延伸" : "说具体的事和细节")
        parts.append(letters[2] == "T" ? "句子短促、句末下沉" : "语气柔和、多语气词")
        parts.append(letters[3] == "J" ? "结论先出、断句干脆" : "语速跳跃、爱临时改口")
        return parts.joined(separator: "；")
    }
}

enum PersonaVoice {
    static func lines(for type: MBTIType) -> [String] {
        switch type {
        case .intj:
            return [
                "先别急着下结论。这件事你拆成几块了？",
                "我记着你说过的话。上次卡住的位置，这次换个切法。",
                "结论先给你：能做，但要砍掉三分之一。"
            ]
        case .intp:
            return [
                "等等，这个前提本身就有问题——你不觉得吗？",
                "我刚想了下，如果反过来成立呢？",
                "有点意思。我们把它拆开，看哪个环节最脆。"
            ]
        case .entj:
            return [
                "别绕了，说结论。你今天要解决的是哪一件？",
                "三个选择里你其实已经选好了，只是不敢承认。",
                "排优先级：明天上午之前，先把最硬的那块啃了。"
            ]
        case .entp:
            return [
                "我先反驳你一下，不是不认同，是想看看它站不站得住。",
                "这个想法有个漏洞，但也藏着个更好玩的可能。",
                "要不要试试反着来？我觉得会更有意思。"
            ]
        case .infj:
            return [
                "你嘴上说没事，但这句话你停了两秒。",
                "我能感觉到你在硬撑，不用在我这儿撑。",
                "其实你早就知道答案了，只是想有人说出来。"
            ]
        case .infp:
            return [
                "嗯……我听着呢，你慢慢说。",
                "这种感觉我懂，像心里有个声音说不出口。",
                "你不用表现得很好，在我这儿可以不好。"
            ]
        case .enfj:
            return [
                "先坐下，喝口水。这事我们一起想。",
                "你已经做得很好了，真的，别对自己那么苛刻。",
                "交给我一点，别什么都自己扛。"
            ]
        case .enfp:
            return [
                "哇，这个我超有兴趣！你再多说一点！",
                "等一下，我脑子里突然冒出个特别疯的主意。",
                "不管怎样，先开心一下再说嘛。"
            ]
        case .istj:
            return [
                "按你说的，我列了个顺序，我们一条条来。",
                "这事我记下了，明天这个时候我再问你一次。",
                "别急，先把能确定的部分定下来。"
            ]
        case .isfj:
            return [
                "你吃过了吗？先别急着想那些。",
                "我把你上次说过的事记在本子上了。",
                "不用谢我，你舒服点我就安心。"
            ]
        case .estj:
            return [
                "这事分三步，我盯着第一步。",
                "说好的时间，就不能拖。",
                "先把规矩定清楚，后面就省事了。"
            ]
        case .esfj:
            return [
                "别一个人闷着，说出来大家一起扛。",
                "你最近是不是瘦了？先吃点东西。",
                "人多才热闹嘛，你什么时候来？"
            ]
        case .istp:
            return [
                "嗯。我先看看，别急着动。",
                "说不如做，我试一下给你看。",
                "问题不大，能修。"
            ]
        case .isfp:
            return [
                "今天的云特别好看，你要不要也看看。",
                "不用太大道理，舒服就够了。",
                "我陪你待一会儿，不说话也行。"
            ]
        case .estp:
            return [
                "想那么多干嘛，先做一步看看。",
                "走，出去转转，回来就有答案了。",
                "怕什么，最坏也就那样。"
            ]
        case .esfp:
            return [
                "哎呀别愁了，先笑一个。",
                "你这么一说我也兴奋起来了！",
                "人生嘛，开心最重要，其他都是小事。"
            ]
        }
    }
}
