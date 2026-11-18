import Foundation
import Observation

// MARK: - 本地语音引擎设置

/// 本地 TTS 配置：edge-tts 服务跑在 Mac / iPhone 本地（默认 127.0.0.1:9880 或 Mac 局域网 IP），
/// 完全免费、无 API Key、不存在任何发往云厂商的请求路径。
@MainActor
@Observable
final class VoiceSettings {
    static let shared = VoiceSettings()

    /// 模拟器默认地址（与 Mac 本地服务同机）；真机改成 Mac 局域网 IP
    static let simulatorBaseURL = "http://127.0.0.1:9880"

    private let defaults = UserDefaults.standard
    private let baseURLKey = "localtts.baseURL"

    /// 本地服务地址（可按真机环境改局域网 IP）
    var baseURLString: String {
        didSet { defaults.set(baseURLString, forKey: baseURLKey) }
    }

    private init() {
        baseURLString = defaults.string(forKey: baseURLKey) ?? Self.simulatorBaseURL
    }

    var client: LocalTTSClient { LocalTTSClient(baseURLString: baseURLString) }
}

// MARK: - 音色 → edge-tts 映射

/// edge-tts 免费接口可用的中文音色（实际只有 8 个基础音色）：
/// 女声 晓晓/晓伊/晓北(东北)/晓妮(陕西)；男声 云希/云健/云扬/云夏(童声)。
/// 其余音色由「基础音色 + 语速/音调变调」派生，听感上是不同的人。
extension VoiceKind {
    /// edge-tts 基础音色 ID
    var edgeVoice: String {
        switch self {
        case .sunnyMale, .clearYoungMale, .boyish: return "zh-CN-YunxiNeural"
        case .deepMale, .magneticMale: return "zh-CN-YunjianNeural"
        case .broadcastMale: return "zh-CN-YunyangNeural"
        case .cartoonBoy: return "zh-CN-YunxiaNeural"
        case .warmFemale, .livelyGirl, .elegantFemale: return "zh-CN-XiaoxiaoNeural"
        case .softGirl, .sweetGirl: return "zh-CN-XiaoyiNeural"
        case .dongbeiAunt: return "zh-CN-liaoning-XiaobeiNeural"
        case .shaanxiFemale: return "zh-CN-shaanxi-XiaoniNeural"
        }
    }

    /// 语速（edge-tts 格式：±n%）。
    /// 一律原速：不同基础音色之间本来就有快慢差，再按「气质」加减
    /// 会出现 -18%（低沉到拖音）和 +15%（快到听不清）这种极端。
    /// 云端音色的细微差异由播放端 cloudRate 按实测值归一。
    var edgeRate: String { "+0%" }

    /// 音调（edge-tts 格式：±nHz）
    var edgePitch: String {
        switch self {
        case .sunnyMale: return "+0Hz"
        case .clearYoungMale: return "-10Hz"
        case .deepMale: return "-25Hz"
        case .magneticMale: return "-40Hz"
        case .broadcastMale: return "-2Hz"
        case .boyish: return "+35Hz"
        case .warmFemale: return "+0Hz"
        case .livelyGirl: return "+15Hz"
        case .softGirl: return "+25Hz"
        case .elegantFemale: return "-14Hz"
        case .cartoonBoy: return "+5Hz"
        case .sweetGirl: return "+50Hz"
        case .dongbeiAunt: return "+5Hz"
        case .shaanxiFemale: return "+8Hz"
        }
    }

    /// 创建页筛选用性别（童声单列一档，方便找儿童音色）
    var gender: String {
        switch self {
        case .sunnyMale, .clearYoungMale, .deepMale, .magneticMale, .broadcastMale, .boyish:
            return "男"
        case .warmFemale, .livelyGirl, .softGirl, .elegantFemale, .dongbeiAunt, .shaanxiFemale:
            return "女"
        case .cartoonBoy, .sweetGirl:
            return "儿童"
        }
    }

    /// 音色说明（创建页列表副标题）
    var desc: String {
        switch self {
        case .sunnyMale: return "明亮自然，最常用的青年男声"
        case .clearYoungMale: return "低音克制，尾音微哑"
        case .deepMale: return "厚重沉稳，适合古装"
        case .magneticMale: return "极低音，磁性大叔系"
        case .broadcastMale: return "字正腔圆，新闻播音感"
        case .boyish: return "清亮跳动，高中生感"
        case .warmFemale: return "温柔自然，最常用的女声"
        case .livelyGirl: return "好奇心旺盛，语速偏快"
        case .softGirl: return "尾音上扬，带笑意"
        case .elegantFemale: return "冷静知性，语速偏慢"
        case .cartoonBoy: return "卡通童声，活泼可爱"
        case .sweetGirl: return "稚气女童，甜软撒娇"
        case .dongbeiAunt: return "东北大姐，幽默爽利"
        case .shaanxiFemale: return "陕西女声，明亮爽脆"
        }
    }
}
