import SwiftUI
import Speech
import AVFoundation
import UIKit

// MARK: - 语音通话模型
// 点【通话】→ 回铃音拨号约 6 秒（两声）→ 对方接通 → 先打招呼 → 麦克风常开、静音 1.6s 自动断句。
//
// 这是一通「陪伴电话」，不是问答机器人。用户不说话的时候，角色就该一直说下去：
//   接通先招呼 → 25s 轻声确认在不在 → 45s 起连着碎碎念（句间只留一口气）
//   → 3 分钟判定「不开心」并安慰 → 3.5 分钟讲三个笑话 → 之后换成更软的陪伴
//   → 8 分钟说结束语「你可以随时打给我」→ 挂断
// 用户一开口，角色立刻停下让位；说完再安静 25 秒，自己又接上。
// 自愈能力：端上识别失效自动切联网识别 / 合成卡死 15s 强制复位 / 回复期间说的话不丢 / 错误上屏。

/// 通话阶段：拨号中（只听回铃音）→ 已接通（开始收音与计时）
enum CallPhase { case dialing, connected }

@MainActor
@Observable
final class VoiceCallModel {
    private(set) var phase: CallPhase = .dialing
    private(set) var isMicOn = true          // 默认开麦
    private(set) var isSpeakerOn = true      // 默认免提
    /// 用户主动按过「扬声器」：接通蓝牙后仍然优先外放，直到下次插拔设备
    private var speakerOverride = false
    /// 真实出声设备（给通话页按钮显示，光看 isSpeakerOn 会误标成「扬声器」）
    private(set) var outputRouteName = "扬声器已开"
    private(set) var outputRouteIcon = "speaker.wave.2.fill"
    private(set) var isEngineRunning = false // 识别引擎是否在收音
    private(set) var transcript = ""         // 用户正在说的话（实时转写）
    private(set) var duration = 0            // 通话秒数（接通后才开始计）
    private(set) var statusNote = ""         // 权限/异常提示
    private(set) var latestReply = ""        // AI 最近一条回复
    /// 实时音量 0~1（只给插话判定用）。
    /// 用 @ObservationIgnored：麦克风每 40ms 进来一帧，如果触发 SwiftUI 重绘，
    /// 整页（大图 + 渐变 + 动效）每秒会被重算二十多次，看起来就是「卡顿」。
    @ObservationIgnored private(set) var inputLevel: Double = 0
    /// 现场诊断（-CallDebug 时才更新并显示）
    private(set) var debugLine = ""
    /// 回复边生成边念：已排入朗读的字符数、待念句子、当前回复的消息 id
    private var replySpokenCount = 0
    private var replyMessageID: UUID?
    /// 用户抢话后，别再把这轮剩下的话念出来
    private var replySpeechCancelled = false
    private var speechQueue: [String] = []
    /// 这一轮从「说完」到「它开口」的耗时，用来定位到底慢在哪一段
    private var turnSentAt = Date.distantPast
    private(set) var lastTurnLatency: TimeInterval = 0
    /// 自动挂断（冷场流程走完），View 监听后关闭页面
    private(set) var shouldHangUp = false

    var isDialing: Bool { phase == .dialing }
    var isConnected: Bool { phase == .connected }

    let chatModel: ChatModel
    private let character: Character
    private let userName: String               // 用户昵称（电话招呼语里用）
    private let voice = VoiceService.shared
    private let ringback = RingbackTone()
    private var ringTask: Task<Void, Never>?
    private var timer: Timer?
    private var monitorTask: Task<Void, Never>?
    private var lastVoiceTime = Date()       // 最近一次检测到说话声
    /// 连续超过人声阈值的音频帧数：用来把「说话」和「环境噪音」分开
    private var loudStreak = 0
    private var lastSpeakEnd = Date.distantPast  // 角色说完话的时刻（防回声）
    /// 用户最后一次开口（或刚接通）的时刻：整条冷场情绪时间轴都从这儿算
    private var silenceStart = Date()
    /// 角色上一句说完的时刻（控制碎碎念 / 陪伴的间隔）
    private var lastLineAt = Date.distantPast
    /// 上一帧角色是否在说话：用来捕捉「刚说完」的那一下
    private var wasSpeaking = false
    /// 正在按剧本念一段（安慰、笑话、结束语）——期间不插碎碎念
    private var scriptTask: Task<Void, Never>?
    private var scriptRunning = false
    private var scriptStartedAt = Date.distantPast

    // ---- 音频会话被抢占 / 系统重置 ----
    /// 被别的 App（来电、语音消息、导航）打断的起始时刻；nil = 没被打断
    private var interruptionStartedAt: Date?
    /// 这次打断持续了多久：恢复时用来决定要不要交代一句「刚才断了」
    private var interruptedFor: TimeInterval = 0
    /// 需要重新抢回音频（打断结束 / 媒体服务重置 / 回到前台）
    private var needsAudioRecovery = false
    private var nextAudioRetryAt = Date.distantPast
    private var interruptionObserver: NSObjectProtocol?
    private var mediaResetObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var configurationObserver: NSObjectProtocol?
    /// 路由切换防抖：蓝牙会在 A2DP / HFP 之间跳一次，立刻重装 tap 会直接崩
    private var routeRecoveryTask: Task<Void, Never>?

    // ---- 抢话（barge-in）----
    /// 角色开口的时刻：刚开始播的 0.8 秒内不判定抢话，先让回声基线稳定
    private var speechStartedAt = Date.distantPast
    /// 说话期间麦克风的底噪（自己声音漏进来的部分），用来定抢话阈值
    private var echoBaseline: Double = 0
    private var bargeFrames = 0

    private var audioEngine = AVAudioEngine()
    /// 音频 tap 在实时线程里跑，不能直接读 @MainActor 的 request；
    /// 用一个小盒子把「当前识别请求」传进去（说话期间会换请求）
    private let requestBox = SpeechRequestBox()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// 麦克风 tap 是否已装（装过没拆就再装会直接崩，必须自己记账）
    private var tapInstalled = false

    // ---- 识别自愈 ----
    /// 识别方式。默认走系统识别（联网，最稳）；端上识别在 zh-CN 上经常
    /// supportsOnDeviceRecognition=true 但模型缺失，静默无结果，只在联网失败后才尝试。
    private enum ASRMode { case server, onDevice }
    // 默认端上识别：不经过网络，出字延迟通常 <300ms。
    // 之前默认云端，要走「上行音频 → 云端识别 → 回包」，网络一抖就慢、就漏字。
    // 端上不可用或连续没有结果时，自愈逻辑会自动切回云端。
    private var asrMode: ASRMode = .onDevice
    private var engineStartedAt = Date.distantPast   // 本次引擎启动时刻
    private var bufferCount = 0                      // 本次引擎收到的音频缓冲数（0 = 麦克风没进音频）
    private var didTryAlternate = false              // 本次故障是否已换过识别方式
    private var asrFailCount = 0                     // 连续识别失败次数（成功转写即清零）
    private var lastResultAt = Date.distantPast      // 最近一次拿到识别结果（含中间结果）
    private var recognitionEnded = false             // 本轮识别任务已结束，需要续听
    /// 最早允许重开麦克风的时刻（失败退避：0.8s → 1.6s → 3.2s，上限 4s。
    /// 通话中绝不永久放弃监听——之前 asrGivenUp 一旦置位麦克风就再也不开了）
    private var asrRestartAt = Date.distantPast
    /// 流式回复还没出完时用户说的话，暂存到回复结束后补发（原实现直接丢弃）
    private var pendingSend: String?
    /// 语音合成卡死看门狗：isPreparing 持续超过 15s 强制复位，否则麦克风永不恢复
    private var prepareSince: Date?

    // 说话停顿多久算「说完了」。端上识别出字快，1.6 秒的等待纯属浪费，
    // 压到 0.9 秒；后面还有「连续两帧人声」的门槛，不会把换气当句尾。
    private static let silenceSendDelay: TimeInterval = 0.9
    /// 判定「有人在说话」的音量线（0~1，rms 放大 6 倍后）
    private static let voiceThreshold: Float = 0.15
    private static let ringDuration: TimeInterval = 6           // 拨号回铃音时长（约两声，别让人干等）

    /// 验收辅助：`-CallSpeed 12` 把整条情绪时间轴压缩 12 倍，
    /// 用来在几十秒内看完「招呼 → 轻问 → 安慰 → 笑话 → 结束语」的完整弧线。
    private static let speed: Double = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-CallSpeed"),
              index + 1 < args.count,
              let value = Double(args[index + 1]), value > 0 else { return 1 }
        return value
    }()

    /// `-CallDebug` 时在通话页显示实时电平/识别状态，用来在真机上调插话阈值
    static let debugEnabled = ProcessInfo.processInfo.arguments.contains("-CallDebug")

    // 情绪时间轴（秒，从「用户最后一次开口」起算，接通即开始）
    private static let checkInAt: TimeInterval = 12 / speed     // 接通后第一次轻声确认「在吗」
    private static let firstChatterAt: TimeInterval = 22 / speed // 初次冷场：先安静一会儿再自说自话
    private static let resumeChatterAt: TimeInterval = 3 / speed // 用户说完又安静下来：3 秒就接上，不冷场
    private static let comfortAt: TimeInterval = 180 / speed    // 3 分钟：判定「不开心」并安慰
    private static let jokesAt: TimeInterval = 215 / speed      // 安慰之后：三个笑话
    private static let companyAt: TimeInterval = 270 / speed    // 笑话讲完：换成更软的陪伴
    private static let closeAt: TimeInterval = 480 / speed      // 8 分钟：结束语 → 挂断
    // 碎碎念是「连着说」，不是一句一句念课文：句间只留一口气，
    // 再叠加上下一句已经预合成好的音频，听起来就是自然的换气。
    private static let chatterGap: TimeInterval = 1.8 / speed
    private static let companyGap: TimeInterval = 2.2 / speed

    /// 冷场推进：idle → checkIn → chatter → comfort → jokes → company → closing
    private enum ColdStage { case idle, checkIn, chatter, comfort, jokes, company, closing }
    private var coldStage: ColdStage = .idle
    /// 这通电话里用户说过话没有：说过之后就不再问「在吗」，安静 25s 直接接上碎碎念
    private var userHasSpoken = false
    private var didCheckIn = false
    /// 安慰和笑话整通电话只走一次——重复问「你是不是不开心」、重复讲同一个笑话比不说话更糟
    private var didComfort = false
    private var didJokes = false
    private var chatterIndex = 0
    /// 这通电话里已经念过的台词（同一通电话内不重复）
    private var spokenSet: Set<String> = []
    private var spokenOrder: [String] = []
    private var companyIndex = 0
    private var chatterPool: [String] = VoiceCallModel.defaultChatter
    private var comfortPool: [String] = []
    private var jokePool: [String] = []
    private var companyPool: [String] = []

    /// 内置碎碎念语料（模型未就绪时也能说；模型可用时会用更贴人设的话排在前面）
    private static let defaultChatter: [String] = [
        "你是不开心嘛，是工作上的事，还是人际上的事？",
        "需要我帮你出主意，还是只需要我听你吐槽？",
        "想一个人静静，还是想出去走走？",
        "不方便说也没关系，我就在这儿陪着你。",
        "我在想，你是不是一个人扛太久了。",
        "别嫌我啰嗦，我就是放心不下你。",
        "你今天吃饭了吗？别又不按时吃。",
        "有话想说就说，没话我就陪你安静一会儿。",
        "其实我更担心你什么都不说。",
        "要是累了，就别硬撑着，先歇一会儿。",
        "你不出声，我就当你在听。",
        "不管你遇到什么事，都别自己憋着。",
        "我先不催你，等你想说的时候再开口。",
        "要不我讲点别的，让你分分心？",
        "（轻声）你不出声，我也听得出你不太对劲。",
        "天塌下来也有我陪你顶着。",
        "没关系的，在我这儿你不用装。",
        "你先忙你的，我不挂，就听着。"
    ]

    init(chatModel: ChatModel, userName: String = "") {
        self.chatModel = chatModel
        self.character = chatModel.character
        self.userName = userName
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        // 通话期间回复走「电话口吻」：短句、口语、没有括号动作
        chatModel.replyContext = .call
        // AI 回合结束 → 用角色声音朗读
        chatModel.onReplyFinished = { [weak self] reply in
            guard let self else { return }
            self.latestReply = reply
            // 正在被打断（来电/别的 App 占用音频）就别硬播，播出来也是哑的；
            // 恢复后由 resumeLine 接上，回复本身已经落在聊天记录里
            guard self.interruptionStartedAt == nil else { return }
            guard !self.replySpeechCancelled else { return }
            // 把最后一段（可能没有句号）补进队列；前面几句多半已经在念了
            if reply.count > self.replySpokenCount {
                let tail = String(reply.dropFirst(self.replySpokenCount))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { self.speechQueue.append(tail) }
                self.replySpokenCount = reply.count
            }
            self.pumpSpeechQueue()
            // 回复念着的时候就把下一句碎碎念备好：3 秒后接上时不用再等合成
            self.prefetch(self.peekNext(self.chatterPool, from: self.chatterIndex))
        }
    }

    // UI 推导状态
    var isThinking: Bool { chatModel.isStreaming }
    var isSpeaking: Bool { voice.speakingID == character.id }
    var isListening: Bool { isEngineRunning && isMicOn }

    var durationText: String {
        isDialing ? "正在接通" : String(format: "%02d:%02d", duration / 60, duration % 60)
    }

    var statusText: String {
        if !statusNote.isEmpty { return statusNote }
        if isDialing { return "正在呼叫…" }
        // 复合错误要在通话页可见——之前失败完全隐身，用户只觉得「装聋」
        if let error = chatModel.lastError { return "没听清（\(error)），请再说一遍" }
        if isSpeaking { return "正在说话…" }
        if isThinking { return "正在思考…" }
        if isListening { return "正在聆听…" }
        if !isMicOn { return "麦克风已关，TA 听不见你" }
        return "请说话"
    }

    // MARK: 通话生命周期

    /// 拨号阶段：只响回铃音，不开麦、不计时、不打招呼；权限弹窗趁响铃时弹
    func startCall() {
        phase = .dialing
        duration = 0
        statusNote = ""
        silenceStart = Date()
        // 新的一通电话：情绪弧线从头来
        userHasSpoken = false
        didComfort = false
        didJokes = false
        chatterIndex = 0
        companyIndex = 0
        resetColdFlow()
        prepareCallScripts()
        registerAudioObservers()

        // 权限预检：缺权限现在就弹/就提示，别等接通后才发现听不见
        // （-DemoCall 是自动演示/截图用的，跳过弹窗，免得挡住整条时间轴）
        let isDemo = ProcessInfo.processInfo.arguments.contains("-DemoCall")
        let speechOK = SFSpeechRecognizer.authorizationStatus() == .authorized
        let micOK = AVAudioSession.sharedInstance().recordPermission == .granted
        if !isDemo, !speechOK || !micOK { requestPermissions() }

        ringback.start()
        ringTask = Task { [weak self] in
            // 响两声就接（回铃音一响一停为一句），别让人干等二十秒
            try? await Task.sleep(for: .seconds(Self.ringDuration))
            guard let self, !Task.isCancelled else { return }
            self.connect()
        }
        scheduleDemoSpeakIfNeeded()
    }

    /// 验收辅助：`-DemoSpeak "我今天有点累"` 在接通两秒后模拟用户说一句话，
    /// 用来验证「用户开口 → 人物正常回复 → 不马上碎碎念」这条链路（模拟器里没法真说话）
    private func scheduleDemoSpeakIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-DemoSpeak"), index + 1 < args.count else { return }
        let text = args[index + 1]
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.ringDuration + 6))
            guard let self, self.isConnected else { return }
            self.cancelScript()
            self.transcript = text
            self.lastVoiceTime = Date()
            try? await Task.sleep(for: .milliseconds(500))
            self.sendTranscript()
        }
    }

    /// 对方接听：停回铃音 → 开始计时 → 先打招呼 → 开麦监听
    private func connect() {
        guard phase == .dialing else { return }
        ringTask = nil
        ringback.stop()
        phase = .connected
        duration = 0
        // 打招呼这一句也算「角色在说话」，所以要记在剧本队列里，
        // 不然冷场流程会在招呼念到一半时插一句碎碎念
        silenceStart = Date()
        resetColdFlow()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.duration += 1 }
        }

        // 接通先把音频会话锁到「通话」类别：喇叭外放 + 麦克风同时可用。
        // 不锁的话，角色一开口（TTS 走 .playback）麦克风就被系统切断，之后只会「正在聆听」
        CallAudioSession.activate()
        // 有蓝牙/耳机就让声音留在它们身上；以前这里无条件 override 到 speaker，
        // AirPods 一连就「听不到声音」
        syncOutputRouteAfterDeviceChange()
        // 蓝牙路由有时比会话激活晚一拍才落定：1.2 秒后再确认一次，
        // 免得刚接通那一下把声音钉在外放上
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, self.isConnected, self.hasExternalAudioRoute(), self.isSpeakerOn else { return }
            self.syncOutputRouteAfterDeviceChange()
        }

        // 通话中打开距离感应：手机贴到耳边屏幕自动熄灭，离开又亮起来。
        // 熄屏不打断声音——App 有后台音频权限（Info.plist UIBackgroundModes），
        // 这也是「手机放在耳边像真打电话」该有的样子。
        UIDevice.current.isProximityMonitoringEnabled = true

        // 角色接通：用「电话味」的专属招呼语喊用户昵称（不是聊天开场白）
        let greeting = CallScript.greeting(for: character, userName: userName)
        chatModel.appendCallGreeting(greeting)
        // 先把麦克风引擎拉起来（权限还没批会给提示，monitorLoop 会继续重试）：
        // 招呼语念的时候用户就能插话，不用等第一句说完
        beginRecording()
        perform([greeting])
        monitorTask = monitorLoop()
    }

    func hangUp() {
        // 记下这通电话说过的句子，下一通排到队尾，别每次都是那几句
        saveRecentLines()
        unregisterAudioObservers()
        ringTask?.cancel()
        ringTask = nil
        ringback.stop()
        monitorTask?.cancel()
        monitorTask = nil
        scriptTask?.cancel()
        scriptTask = nil
        scriptRunning = false
        timer?.invalidate()
        timer = nil
        stopEngine()
        voice.stop()
        chatModel.onReplyFinished = nil
        chatModel.replyContext = .chat       // 挂断后回到文字聊天口吻
        voice.lineRateScale = 1              // 文字聊天的语速恢复原值
        UIDevice.current.isProximityMonitoringEnabled = false
        CallAudioSession.deactivate()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 输出路由（蓝牙 / 耳机 / 外放 / 听筒）

    private func hasExternalAudioRoute() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
                 .headphones, .headsetMic, .usbAudio, .carAudio:
                return true
            default:
                return false
            }
        }
    }

    /// 真正决定「声音从哪儿出来」：连了蓝牙/耳机就跟着它们，
    /// 只有用户主动按「扬声器」才抢回外放。
    private func applyOutputRoute() {
        let session = AVAudioSession.sharedInstance()
        let external = hasExternalAudioRoute()
        let wantSpeaker = isSpeakerOn && (!external || speakerOverride)
        try? session.overrideOutputAudioPort(wantSpeaker ? .speaker : .none)
        refreshOutputLabel(wantSpeaker: wantSpeaker, external: external)
    }

    /// 插拔设备：重置手动选择，跟着新设备走（AirPods 一连就该切过去）
    private func syncOutputRouteAfterDeviceChange() {
        let external = hasExternalAudioRoute()
        speakerOverride = false
        isSpeakerOn = !external
        applyOutputRoute()
    }

    private func refreshOutputLabel(wantSpeaker: Bool, external: Bool) {
        if wantSpeaker {
            outputRouteName = "扬声器已开"
            outputRouteIcon = "speaker.wave.2.fill"
            return
        }
        guard external, let port = AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType else {
            outputRouteName = "听筒"
            outputRouteIcon = "speaker.slash.fill"
            return
        }
        switch port {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            outputRouteName = "蓝牙耳机"
            outputRouteIcon = "wave.3.right"
        case .carAudio:
            outputRouteName = "车载音响"
            outputRouteIcon = "car.fill"
        case .usbAudio:
            outputRouteName = "USB 音频"
            outputRouteIcon = "cable.connector"
        default:
            outputRouteName = "耳机"
            outputRouteIcon = "headphones"
        }
    }

    // MARK: - 音频被抢占 / 系统重置 / 回到前台

    /// 通话期间注册：来电、语音消息、导航播报都会抢走音频会话。
    /// 不处理的话，App 会永远停在「静音 / 正在聆听」的死状态，用户以为电话断了。
    private func registerAudioObservers() {
        unregisterAudioObservers()
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in self?.handleInterruption(note) }
        }
        mediaResetObserver = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleMediaServicesReset() }
        }
        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in self?.handleRouteChange(note) }
        }
        activeObserver = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestAudioRecovery() }
        }
        // 引擎自身的配置变化（路由变了、格式变了）也要重建，否则之后 start 会一直报 'what'
        configurationObserver = center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRouteRecovery() }
        }
    }

    private func unregisterAudioObservers() {
        let center = NotificationCenter.default
        [interruptionObserver, mediaResetObserver, routeChangeObserver,
         activeObserver, configurationObserver]
            .compactMap { $0 }
            .forEach { center.removeObserver($0) }
        interruptionObserver = nil
        mediaResetObserver = nil
        routeChangeObserver = nil
        activeObserver = nil
        configurationObserver = nil
        routeRecoveryTask?.cancel()
        routeRecoveryTask = nil
    }

    private func handleInterruption(_ note: Notification) {
        guard isConnected else { return }
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            guard interruptionStartedAt == nil else { return }
            interruptionStartedAt = Date()
            // 系统已经把声音掐了，自己的状态也要清干净：
            // 否则 speakingID 一直挂着，麦克风永远不恢复（表现就是「彻底哑了」）
            voice.stop()
            // 注意：这里**不取消剧本**。微信播一条语音是几秒钟的短打断，
            // 以前一打断就 cancelScript + 补一句「刚才断了」，
            // 一来一回就是「断断续续」。短打断结束后接着往下念就好。
            stopEngine()
            statusNote = "被其他 App 占用音频，稍等一下"
        case .ended:
            let options = AVAudioSession.InterruptionOptions(
                rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            )
            handleInterruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            break
        }
    }

    private func handleInterruptionEnded(shouldResume: Bool) {
        guard let started = interruptionStartedAt else { return }
        interruptionStartedAt = nil
        let paused = Date().timeIntervalSince(started)
        // 只有「真的断了很久」（来电、接了别的电话）才值得补一句「刚才断了」；
        // 微信播一条语音这种两三秒的打断，安静接上就行，别每次都重来一遍
        interruptedFor = paused > 8 ? paused : 0
        // 被打断的这几分钟不能算「用户一直不说话」：整条时间轴一起后移，
        // 否则一恢复就直接跳到「3 分钟安慰」甚至到点挂断
        silenceStart = silenceStart.addingTimeInterval(paused)
        lastLineAt = lastLineAt.addingTimeInterval(paused)
        lastVoiceTime = Date()
        // 主动抢一次；抢不到由 monitorLoop 每 2 秒重试（别的 App 可能还占着）
        needsAudioRecovery = true
        nextAudioRetryAt = Date()
        statusNote = paused > 8
            ? (shouldResume ? "正在恢复通话…" : "其他 App 还占着音频，正在重连…")
            : ""
    }

    private func handleMediaServicesReset() {
        guard isConnected else { return }
        // 媒体服务重启后旧引擎的节点全部失效，这时候 removeTap / stop 都可能直接崩，
        // 整个丢掉换新的最安全
        discardAudioEngine()
        requestAudioRecovery(note: "音频服务被系统重置，正在恢复…")
    }

    /// 丢掉当前引擎（连同 tap），但不尝试拆 tap：
    /// 路由切换 / 媒体服务重置后旧节点可能已经失效，removeTap 反而会崩。
    private func discardAudioEngine() {
        requestBox.request = nil
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        transcript = ""
        inputLevel = 0
        loudStreak = 0
        isEngineRunning = false
        tapInstalled = false
        audioEngine.stop()
        audioEngine = AVAudioEngine()
    }

    private func handleRouteChange(_ note: Notification) {
        guard isConnected else { return }
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable:
            // 插拔蓝牙/耳机：输出跟着新设备走，输入格式也变了，旧 tap 得重装
            syncOutputRouteAfterDeviceChange()
            scheduleRouteRecovery()
        case .routeConfigurationChange:
            scheduleRouteRecovery()
        default:
            break
        }
    }

    /// 路由切换不能立刻重装 tap：蓝牙会在 A2DP / HFP 之间跳一次，
    /// 在切换中途 installTap / start 会直接抛 'what'（2003329396）甚至闪退。
    /// 这里防抖 0.9 秒，等系统落定后换一个新引擎再起。
    private func scheduleRouteRecovery() {
        guard isConnected else { return }
        routeRecoveryTask?.cancel()
        routeRecoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled, self.isConnected else { return }
            self.discardAudioEngine()
            self.needsAudioRecovery = true
            self.nextAudioRetryAt = Date()
        }
    }

    /// 请求恢复音频（真正的重试统一放在 monitorLoop 里，避免多处同时抢会话）
    private func requestAudioRecovery(note: String? = nil) {
        guard isConnected else { return }
        needsAudioRecovery = true
        nextAudioRetryAt = Date()
        if let note { statusNote = note }
    }

    /// 重新激活会话并补开麦克风；失败就 2 秒后再来（别的 App 还占着是常态）
    private func tryRecoverAudioIfNeeded() {
        guard needsAudioRecovery, isConnected else { return }
        guard Date() >= nextAudioRetryAt else { return }
        do {
            CallAudioSession.activate()
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true)
            applyOutputRoute()
            needsAudioRecovery = false
            statusNote = ""
            // 系统没发 .ended（App 在后台被挂起过）：补一次时间轴后移
            if let started = interruptionStartedAt {
                let paused = Date().timeIntervalSince(started)
                interruptionStartedAt = nil
                interruptedFor = max(interruptedFor, paused)
                silenceStart = silenceStart.addingTimeInterval(paused)
                lastLineAt = lastLineAt.addingTimeInterval(paused)
            }
            if isMicOn { beginRecording() }
            let paused = interruptedFor
            interruptedFor = 0
            // 打断超过 3 秒：像真人一样交代一句，别让对方以为电话断了
            if paused > 3, !scriptRunning, !isSpeaking, !voice.isPreparing {
                perform([CallScript.resumeLine(for: character, userName: callName)])
            }
        } catch {
            nextAudioRetryAt = Date().addingTimeInterval(2)
            statusNote = "音频被其他 App 占用，正在重连…"
        }
    }

    // MARK: 底部三按钮

    func toggleMic() {
        isMicOn.toggle()
        statusNote = ""
        // 拨号中不开麦：还没接通，麦克风不该工作
        if isMicOn, isConnected {
            silenceStart = Date()
            beginRecording()
        } else if !isMicOn {
            transcript = ""
            stopEngine()
        }
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        // 手动选择要记住：下一次开麦重设会话时不能又把它让回蓝牙
        speakerOverride = isSpeakerOn
        applyOutputRoute()
    }

    // MARK: 常驻监控：回声避让 / 自动断句 / 冷场关怀 / 断线自愈

    private func monitorLoop() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                guard let self else { return }
                // 音频被抢走后要自己抢回来：来电结束 / 别的 App 播完 / 回前台都走这里
                self.tryRecoverAudioIfNeeded()
                // 边生成边念：有完整句子就念，别等整段
                self.harvestReplySentences()
                self.pumpSpeechQueue()
                // 诊断数据一直算（一行字符串，开销可以忽略），是否显示由界面开关决定
                self.debugLine = String(
                    format: "eng %@ rec %@ spk %@ | lv %.2f base %.2f bf %d | lat %.1fs",
                    self.isEngineRunning ? "1" : "0",
                    self.task != nil ? "1" : "0",
                    self.isSpeaking ? "1" : "0",
                    self.inputLevel, self.echoBaseline, self.bargeFrames)
                // 兜底：系统没发 .ended 也不会永远哑着。App 明明在前台、
                // 却已经「被打断」超过 30 秒 → 强制当打断结束处理，重新抢会话。
                if let started = self.interruptionStartedAt,
                   UIApplication.shared.applicationState == .active,
                   Date().timeIntervalSince(started) > 30 {
                    self.handleInterruptionEnded(shouldResume: true)
                }
                // 合成卡死看门狗：4G 下本地服务超时+云端重试可能把 isPreparing 拖住，
                // speakingID 一直占用会让麦克风永不恢复（表现：只播招呼语，之后装聋）
                if self.voice.isPreparing {
                    if self.prepareSince == nil { self.prepareSince = Date() }
                    // 通话里等不起 15 秒：合成卡住就立刻复位，宁可这一句跳过，
                    // 也不能让对面听着听着突然没声了
                    if Date().timeIntervalSince(self.prepareSince!) > 8 {
                        self.voice.stop()
                        self.prepareSince = nil
                        self.statusNote = "语音合成超时，已重置，请再说一遍"
                    }
                } else {
                    self.prepareSince = nil
                }
                // 角色刚说完一句（不管是正常回复还是碎碎念）→ 记下「说完」的时刻。
                // 碎碎念的间隔必须从这里算：以前记在开口那一刻，回复越长间隔越像早过了，
                // 结果人物刚答完话就立刻接着碎碎念，像是在自说自话不等你。
                if self.wasSpeaking, !self.isSpeaking {
                    self.lastLineAt = Date()
                }
                // 刚开口：重置抢话判定的基线
                if !self.wasSpeaking, self.isSpeaking {
                    self.speechStartedAt = Date()
                    self.echoBaseline = 0
                    self.bargeFrames = 0
                }
                self.wasSpeaking = self.isSpeaking

                // 剧本状态卡死兜底：超过 20 秒既没在说也没在合成，说明状态机卡住了。
                // 不解锁的话冷场时间轴会被永久挡住，表现就是「人突然不说话了」。
                if self.scriptRunning, !self.isSpeaking, !self.voice.isPreparing,
                   Date().timeIntervalSince(self.scriptStartedAt) > 20 {
                    self.scriptRunning = false
                }
                // 角色说话时：识别**继续跑**。
                // 之前是「听到抢话才开识别」，用户已经说了大半句，只能抓到尾巴（例如只说「吗？」）；
                // 现在从第一个字就收音，识别结果里把它自己念的话按文本重合度过滤掉。
                if self.isSpeaking {
                    if self.task == nil, Date() >= self.asrRestartAt {
                        self.beginRecording()
                    }
                    if self.shouldYieldToUser() {
                        self.assumeUserIsTalking()
                    }
                    continue
                }
                // 回复出完 → 补发流式期间用户说的话（原实现直接丢弃）
                if !self.isThinking, !self.isSpeaking, let pending = self.pendingSend {
                    self.pendingSend = nil
                    self.silenceStart = Date()
                    self.chatModel.input = pending
                    self.chatModel.send()
                }
                // 麦克风开着但没有识别任务 → 稍等回声散去再补建。
                // 生成回复（isThinking）期间也算：那会儿角色没出声，
                // 用户插话要能收进来，回复结束后由 pendingSend 补发。
                if self.isMicOn,
                   Date().timeIntervalSince(self.lastSpeakEnd) > 0.6,
                   Date() >= self.asrRestartAt {
                    if self.task == nil {
                        self.beginRecording()
                    }
                }
                // 识别自愈：只在「确实开口了却长时间零结果」时轻量重启，
                // 绝不按固定 8 秒暴力杀引擎（旧逻辑每 8 秒清空一次转写，
                // 用户说两句话就被吞掉，之后永远「正在聆听」）
                if self.isEngineRunning, self.transcript.isEmpty,
                   self.lastVoiceTime > self.engineStartedAt {
                    let elapsed = Date().timeIntervalSince(self.engineStartedAt)
                    if self.bufferCount == 0, elapsed > 2.5 {
                        self.statusNote = "麦克风没有收到声音（可能被其他 App 占用）"
                        self.discardAudioEngine()   // 一个字节都没进来，说明引擎坏了，整台换掉
                        self.asrRestartAt = Date().addingTimeInterval(1.5)
                        continue
                    }
                    // 有人声、有音频，12 秒却一个字都没出来 → 换识别方式试一次
                    // 端上识别 5 秒还没出字，就别死守了，直接换云端
                    if self.bufferCount > 8, elapsed > 5,
                       Date().timeIntervalSince(self.lastResultAt) > 5 {
                        if !self.didTryAlternate {
                            self.didTryAlternate = true
                            self.asrMode = (self.asrMode == .server) ? .onDevice : .server
                            self.statusNote = "换一种识别方式再试…"
                            self.stopRecognition()   // 只换识别任务，不拆麦克风引擎
                            self.asrRestartAt = Date().addingTimeInterval(0.8)
                        } else if elapsed > 30 {
                            // 端上识别经常「一声不响」（模型缺失也不报错），
                            // 不能死守一种方式：满 30 秒换回另一种，并重新给一次机会
                            self.asrFailCount += 1
                            self.asrMode = (self.asrMode == .server) ? .onDevice : .server
                            self.didTryAlternate = false
                            self.statusNote = "识别不太顺，正在换一种方式…"
                            self.stopRecognition()
                            self.asrRestartAt = Date().addingTimeInterval(min(4, 0.8 * Double(self.asrFailCount)))
                        }
                        continue
                    }
                }
                // 用户明明在出声、识别却 3 秒一个字都没出 → 立刻换一轮识别，
                // 别让人对着空气重复第二遍（「有时候识别不到」的直接补丁）
                if self.task != nil, self.transcript.isEmpty,
                   Date().timeIntervalSince(self.lastVoiceTime) < 0.8,
                   Date().timeIntervalSince(self.engineStartedAt) > 3,
                   Date().timeIntervalSince(self.lastResultAt) > 3 {
                    self.stopRecognition()
                    self.asrRestartAt = Date().addingTimeInterval(0.2)
                }
                // 说完一段话：转写非空且静音超过 1.6s → 自动发送
                if self.isEngineRunning,
                   !self.transcript.isEmpty,
                   Date().timeIntervalSince(self.lastVoiceTime) > Self.silenceSendDelay {
                    self.sendTranscript()
                    continue
                }
                // 冷场情绪时间轴：用户不说话就一直说，用户一开口就停。
                // 初次冷场 12s 轻问、22s 起碎碎念；用户说过话之后再安静 3s 就直接接上。
                // 3min 判定「不开心」并安慰一次 → 3.5min 讲三个笑话 → 之后换成更软的陪伴 → 8min 结束语挂断
                if self.isMicOn, !self.isThinking, self.transcript.isEmpty,
                   !self.isSpeaking, !self.voice.isPreparing, !self.scriptRunning,
                   self.interruptionStartedAt == nil {
                    let silent = Date().timeIntervalSince(self.silenceStart)
                    // 用户这会儿正在出声 → 别抢话（音量 / 转写任一有动静都算）
                    let canSpeak = Date().timeIntervalSince(self.lastVoiceTime) > 1.2
                    // 说过话的人不用再被问「在吗」，25 秒没动静就该接上话了
                    let chatterAt = self.userHasSpoken ? Self.resumeChatterAt : Self.firstChatterAt

                    if silent >= Self.closeAt {
                        self.startClosing()
                    } else if silent >= Self.companyAt {
                        self.companyTick()
                    } else if canSpeak, silent >= Self.jokesAt, !self.didJokes {
                        self.startJokes()
                    } else if canSpeak, silent >= Self.comfortAt, !self.didComfort {
                        self.startComfort()
                    } else if canSpeak, silent >= chatterAt {
                        self.chatterTick()
                    } else if canSpeak, !self.userHasSpoken, silent >= Self.checkInAt, !self.didCheckIn {
                        self.startCheckIn()
                    }
                }
            }
        }
    }

    private func sendTranscript() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = ""
        // 新一轮：重置「边生成边念」的进度
        turnSentAt = Date()
        replySpokenCount = 0
        replyMessageID = nil
        replySpeechCancelled = false
        lastTurnLatency = 0
        speechQueue.removeAll()
        // 只停识别，不动麦克风引擎：来回启停引擎会让正在播的 TTS 卡顿，
        // 也会让插话检测时有时无
        stopRecognition()
        statusNote = ""
        // 过滤纯标点/空白；「嗯」「在」这类单字是真实回答，不能再丢
        let meaningful = text.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0) || $0.value > 0x2E80
        }
        // 没听清 / 只是环境噪音：不能算用户开口。
        // 以前这里无条件重置计时，空调声、衣服摩擦被识别成一个「。」，
        // 冷场计时就永远归零——表现是人物一直不吭声。
        guard meaningful else { return }

        // 用户真的说话了：情绪时间轴重头计，角色正在念的段子也让位
        silenceStart = Date()
        cancelScript()
        resetColdFlow()
        // 之后不再问「在吗」，安静 25s 就直接接上碎碎念
        userHasSpoken = true

        // 上一条还在回复中：暂存，回复结束后由 monitorLoop 补发（原实现直接丢弃）
        guard !chatModel.isStreaming else {
            pendingSend = text
            return
        }
        chatModel.input = text
        chatModel.send()
    }

    // MARK: - 冷场情绪流程

    /// 用户开口后重置冷场阶段，但不清空已经讲过的东西：
    /// 安慰和笑话整通电话只来一次，碎碎念也接着往下轮，不要从头念同一句。
    private func resetColdFlow() {
        coldStage = .idle
        didCheckIn = false
    }

    /// 25 秒没人说话：先轻声确认一句（不是质问，是怕信号断了）
    private func startCheckIn() {
        didCheckIn = true
        coldStage = .checkIn
        perform([CallScript.checkIn(for: character, userName: userName)])
    }

    /// 一个人自说自话：从池里取一句没说过的话，隔一口气再说
    private func chatterTick() {
        guard Date().timeIntervalSince(lastLineAt) > Self.chatterGap else { return }
        guard let line = takeLine(from: chatterPool, index: &chatterIndex) else { return }
        coldStage = .chatter
        perform([line])
        prefetch(peekNext(chatterPool, from: chatterIndex))
    }

    /// 念这句的同时把下一句合成好（错开 0.8 秒，别和当前这句的合成请求撞在一起），
    /// 下一句开口时就能零等待接上，句间只剩自然的换气。
    private func prefetch(_ line: String?) {
        guard let line else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self else { return }
            self.voice.prepare(line, for: self.character)
        }
    }

    /// 3 分钟还没开口 → 判定「不开心」：连说三句安慰，句间留出让他回话的空
    private func startComfort() {
        didComfort = true
        coldStage = .comfort
        let pool = comfortPool.isEmpty ? CallScript.comfort(for: character) : comfortPool
        perform(pool, gap: 3.6 / Self.speed)
    }

    /// 安慰完还是没动静 → 三个笑话，一个接一个，给足反应时间
    private func startJokes() {
        didJokes = true
        coldStage = .jokes
        let pool = jokePool.isEmpty ? CallScript.jokes(for: character) : jokePool
        perform(Array(pool.prefix(3)), gap: 4.8 / Self.speed)
    }

    /// 笑话讲完仍不开口 → 换成更软的语气接着陪，隔一阵说一句
    private func companyTick() {
        guard Date().timeIntervalSince(lastLineAt) > Self.companyGap else { return }
        guard let line = takeLine(from: companyPool, index: &companyIndex) else { return }
        coldStage = .company
        perform([line])
        prefetch(peekNext(companyPool, from: companyIndex))
    }

    /// 8 分钟：结束语 → 等两秒（给用户留一声「嗯」的机会）→ 挂断
    private func startClosing() {
        guard coldStage != .closing else { return }
        coldStage = .closing
        perform([CallScript.farewell(for: character)], gap: 0) { [weak self] in
            guard let self else { return }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.2 / Self.speed))
                guard let self, !Task.isCancelled else { return }
                // 这两秒里用户开口了 → 电话继续，不挂
                guard self.coldStage == .closing else { return }
                self.finishAutoHangUp()
            }
        }
    }

    /// 按顺序念一段台词：一句播完再念下一句。
    /// VoiceService.speak 会先 stop 掉上一句，所以这里必须等 speakingID 归零，不能连着调。
    private func perform(_ lines: [String], gap: TimeInterval = 1.2,
                         then completion: (() -> Void)? = nil) {
        let lines = lines.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        scriptTask?.cancel()
        scriptRunning = true
        scriptStartedAt = Date()
        scriptTask = Task { [weak self] in
            guard let self else { return }
            for (index, line) in lines.enumerated() {
                guard !Task.isCancelled else { return }
                self.scriptStartedAt = Date()      // 每句都刷新，20s 兜底只针对「这句卡住」
                self.say(line)
                // 念这句的同时就把下一句合成好：否则每句都要等 0.5~1.5s 的云端合成，
                // 句间停顿会变得又长又机械
                if index + 1 < lines.count {
                    self.voice.prepare(lines[index + 1], for: self.character)
                }
                try? await Task.sleep(for: .milliseconds(350))
                var waited: TimeInterval = 0
                while self.isSpeaking || self.voice.isPreparing || self.interruptionStartedAt != nil {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(200))
                    // 被别的 App 打断（来电、微信语音）：等它播完再继续。
                    // 这段时间不计入「合成卡住」的超时，否则会被误判成卡死、直接跳句。
                    if self.interruptionStartedAt != nil { continue }
                    waited += 0.2
                    if waited > 12 { break }     // 合成卡住时别把整通电话拖住
                }
                self.lastLineAt = Date()
                if index < lines.count - 1 {
                    // 换气长短随机一点：固定节奏听起来像播报
                    let breath = gap * Double.random(in: 0.85...1.15)
                    try? await Task.sleep(for: .seconds(breath))
                }
            }
            guard !Task.isCancelled else { return }
            self.scriptRunning = false
            completion?()
        }
    }

    /// 说一句（同时上屏，让用户看到 TA 在说什么）
    private func say(_ line: String) {
        // 台词池里有 {name} 占位符，念之前必须替换——以前碎碎念会直接念出「花括号 name」
        let text = CallScript.speakable(line, userName: callName)
        latestReply = text
        // 每句语速微调一点点：同一副嗓子连着念十句，固定语速听起来像播报
        voice.lineRateScale = Float.random(in: 0.96...1.04)
        voice.speak(text, for: character)
    }

    /// 电话里怎么称呼用户：没填昵称就用「你」
    private var callName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "你" : trimmed
    }

    /// 用户开口了：把角色正在念的段落打断，别盖过用户
    private func cancelScript() {
        scriptTask?.cancel()
        scriptTask = nil
        guard scriptRunning else { return }
        scriptRunning = false
        if isSpeaking || voice.isPreparing { voice.stop() }
    }

    /// 通话开场就把整套话术备好：分角色台词打头，再用通用生活碎碎念补量。
    /// 三个措施压重复：
    ///   ① 通用池分两半，碎碎念和陪伴各用一半，同一通电话里不撞句；
    ///   ② 这通电话说过的句子记下来，轮到时跳过；
    ///   ③ 上一通电话说过的句子排到队尾（跨通话也不至于每通都听同样的话）。
    private func prepareCallScripts() {
        spokenSet.removeAll()
        spokenOrder.removeAll()

        let smallTalk = CallScript.smallTalk.shuffled()
        let half = max(1, smallTalk.count / 2)
        let chatterExtra = Array(smallTalk[..<half])
        let companyExtra = Array(smallTalk[half...])

        chatterPool = deprioritizeRecent(CallScript.chatter(for: character).shuffled() + chatterExtra)
        companyPool = deprioritizeRecent(CallScript.company(for: character).shuffled() + companyExtra)
        comfortPool = CallScript.comfort(for: character)
        jokePool = CallScript.jokes(for: character).shuffled()

        guard LLMSettings.shared.isReady else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let lines = try? await Self.generateChatter(for: self.character), !lines.isEmpty else { return }
            self.chatterPool += self.deprioritizeRecent(lines.shuffled())   // 追加在后：先保证角色专属
        }
    }

    // MARK: 台词去重

    private var recentKey: String { "call.recent.\(character.id)" }

    /// 把上一通电话说过的句子挪到队尾，保留原来的相对顺序
    private func deprioritizeRecent(_ lines: [String]) -> [String] {
        let recent = Set(UserDefaults.standard.stringArray(forKey: recentKey) ?? [])
        guard !recent.isEmpty else { return lines }
        return lines.filter { !recent.contains($0) } + lines.filter { recent.contains($0) }
    }

    /// 取下一句：跳过这通电话已经说过的；全说完了才允许从头再轮
    private func takeLine(from pool: [String], index: inout Int) -> String? {
        guard !pool.isEmpty else { return nil }
        for _ in 0..<pool.count {
            let line = pool[index % pool.count]
            index += 1
            if !spokenSet.contains(line) {
                spokenSet.insert(line)
                spokenOrder.append(line)
                return line
            }
        }
        spokenSet.removeAll()
        spokenOrder.removeAll()
        let line = pool[index % pool.count]
        index += 1
        spokenSet.insert(line)
        spokenOrder.append(line)
        return line
    }

    /// 看一眼下一句会是什么（不占位），用来提前合成
    private func peekNext(_ pool: [String], from index: Int) -> String? {
        guard !pool.isEmpty else { return nil }
        for offset in 0..<pool.count {
            let line = pool[(index + offset) % pool.count]
            if !spokenSet.contains(line) { return line }
        }
        return pool[index % pool.count]
    }

    /// 挂断时把这次说过的句子记下来，下一通尽量往后排
    private func saveRecentLines() {
        guard !spokenOrder.isEmpty else { return }
        let previous = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        let merged = Array((spokenOrder.reversed() + previous).prefix(40))
        UserDefaults.standard.set(merged, forKey: recentKey)
    }

    private static func generateChatter(for character: Character) async throws -> [String] {
        let system = PersonaPrompt.system(for: character, level: 4, memory: [], context: .call)
        let user = """
        对方在电话里沉默，很久不说话。你担心但不想逼问，只是一声声地小声念叨、自己跟自己说话，把关心说出来。
        写 8 句你会对着电话独自说出口的话：第一人称，语气和你的性格一致，每句 8~25 字，像自言自语。
        要求：意思各不相同，不要连续质问，不要写括号动作，不要提 AI/模型，不要 Markdown，不要编号。
        每句一行，只输出这 8 句。
        """
        let text = try await LLMClient.completeOnce(system: system, user: user, temperature: 1.05)
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { line -> String in
                // 去掉可能出现的编号/项目符号
                var s = line
                for prefix in ["- ", "* ", "· "] where s.hasPrefix(prefix) {
                    s = String(s.dropFirst(prefix.count))
                }
                let digits = s.prefix { $0.isNumber || $0 == "." || $0 == "、" }
                if !digits.isEmpty { s = String(s.dropFirst(digits.count)) }
                // 电话里没有动作：模型偶尔还是会写括号，这里兜底剥掉
                s = VoiceService.spokenPart(of: s)
                return s.trimmingCharacters(in: .whitespaces)
            }
            .filter { $0.count >= 6 && $0.count <= 80 }
            .prefix(8)
            .map { $0 }
    }

    /// 结束语说完 → 挂断
    private func finishAutoHangUp() {
        hangUp()
        shouldHangUp = true
    }

    // MARK: 语音识别

    /// 开麦：保证引擎在跑 + 建一条识别任务。
    /// 拆成两步是因为「角色说话时」还要靠引擎里的麦克风听用户有没有抢话：
    /// 以前一说话就 stopEngine，用户开口完全没反应。
    private func beginRecording() {
        guard isMicOn, isConnected else { return }

        let speechOK = SFSpeechRecognizer.authorizationStatus() == .authorized
        let micOK = AVAudioSession.sharedInstance().recordPermission == .granted
        guard speechOK, micOK else {
            // 权限不齐：明确告诉用户缺哪个、去哪开（原实现静默递归重试，
            // 权限被拒时 requestPermissions ↔ beginRecording 无限互调、还不显示任何提示，
            // 表现就是「装聋」且毫无线索）
            statusNote = speechOK
                ? "麦克风权限未开启，TA 听不见你（设置 → 夜谈 → 麦克风）"
                : "语音识别权限未开启，TA 听不见你（设置 → 夜谈 → 语音识别）"
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            // 无网 / 语音服务不可用：明说 + 自动重试，别再闷头装听不见
            statusNote = "语音识别暂不可用（检查网络），稍后自动重试"
            asrRestartAt = Date().addingTimeInterval(1.5)
            return
        }

        do {
            // 通话期间引擎只启动一次：之后的「开麦」都只是重建识别任务。
            // 反复 setActive / start 会在 TTS 播放中间插入一次音频重配，听感就是卡顿。
            if !isEngineRunning {
                // 通话中永远保持 .playAndRecord：这是麦克风能被听见的前提
                CallAudioSession.activate()
                let session = AVAudioSession.sharedInstance()
                try session.setActive(true)
                applyOutputRoute()
                try startAudioEngineIfNeeded()
            }
            startRecognition(with: recognizer)
        } catch {
            // 'what'（2003329396）基本都出在「引擎状态坏了 / 路由正在切换」：
            // 换一个新引擎，1.2 秒后再来，别停在「听不见」上
            audioEngine = AVAudioEngine()
            isEngineRunning = false
            tapInstalled = false
            statusNote = "麦克风正在重连…"
            asrRestartAt = Date().addingTimeInterval(1.2)
        }
    }

    /// 装 tap + 启动引擎；已经在跑就直接返回
    private func startAudioEngineIfNeeded() throws {
        guard !isEngineRunning else { return }

        let input = audioEngine.inputNode
        // 打开系统级回声消除（AEC）：外放/蓝牙漏进麦克风的声音会被压掉，
        // 插话判定才不会被自己的声音淹没。必须在装 tap、读格式之前打开。
        try? input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioEngineFailure.invalidInputFormat
        }

        removeTapIfNeeded()
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.requestBox.request?.append(buffer)
            let level = buffer.rmsLevel()
            Task { @MainActor [weak self] in
                self?.ingestInputLevel(level)
            }
        }
        tapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            removeTapIfNeeded()
            audioEngine = AVAudioEngine()       // 这个引擎已经废了，换一个新的
            throw error
        }
        isEngineRunning = true
    }

    /// 建识别任务（引擎必须已经在跑）
    private func startRecognition(with recognizer: SFSpeechRecognizer) {
        guard task == nil else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        // 默认联网识别（最稳）；只有联网失败后才换端上
        if asrMode == .onDevice, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        requestBox.request = request
        engineStartedAt = Date()
        lastResultAt = Date()
        bufferCount = 0
        transcript = ""
        recognitionEnded = false

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleRecognition(result: result, error: error)
            }
        }
        if task == nil {
            // recognizer 拒绝建任务：收拾干净，稍后重试
            stopRecognition()
            statusNote = "识别服务暂时不可用，正在重连…"
            asrRestartAt = Date().addingTimeInterval(1.2)
        }
    }

    /// 只停识别，麦克风继续录：角色说话时要靠它听用户有没有抢话
    private func stopRecognition() {
        requestBox.request = nil
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        transcript = ""
        inputLevel = 0
        loudStreak = 0
    }

    /// 音量进来：说话期间只更新「抢话用的电平」，不刷新 lastVoiceTime
    private func ingestInputLevel(_ level: Float) {
        bufferCount += 1
        inputLevel = Double(level)
        if isSpeaking {
            // 自己说话漏进麦克风的声音不算「用户开口」，
            // 否则冷场计时永远不归零，碎碎念会被一直挡住
            return
        }
        // 只有「连续两帧都到人声量级」才算用户开口。
        // 以前单帧 0.06 就算说话：衣服摩擦、呼吸、街上车声都会过线，
        // lastVoiceTime 一直被刷新，冷场计时永远不归零——表现就是人物很久不说话。
        if level > Self.voiceThreshold {
            loudStreak += 1
            if loudStreak >= 2 { lastVoiceTime = Date() }
        } else {
            loudStreak = 0
        }
    }

    /// 判定用户确实在说话：立刻让出话头。
    /// 关键：**不重置识别**——他说过的前半句已经在 transcript 里了，
    /// 重置会把「你吃饭了」丢掉，只剩最后一个「吗」。
    private func assumeUserIsTalking() {
        guard isSpeaking || voice.isPreparing else { return }
        voice.stop()
        cancelScript()
        speechQueue.removeAll()
        replySpeechCancelled = true
        statusNote = ""
        silenceStart = Date()
        bargeFrames = 0
        echoBaseline = 0
    }

    /// 识别到的文字是不是「自己在念的台词」漏进麦克风的回声。
    /// 中文识别即使有错字，与台词的字符重合度也很高；用户说的内容基本不重合。
    private func isEcho(_ heard: String, spoken: String?) -> Bool {
        guard let spoken, !spoken.isEmpty else { return false }
        let a = heard.filter { $0.isLetter || $0.isNumber }
        let b = spoken.filter { $0.isLetter || $0.isNumber }
        // 太短的不做判定：用户一句「嗯」「好」也可能只有一两个字
        guard a.count >= 4, !b.isEmpty else { return false }
        let hit = a.filter { b.contains($0) }.count
        // 阈值抬高：宁可偶尔把自己的回声当成一句话（顶多停一下），
        // 也不能把用户真正说的话吞掉
        return Double(hit) / Double(a.count) >= 0.75
    }

    /// 边生成边念：把已经生成的完整句子排进队列。
    /// 以前要等整段回复生成完才合成，光这一段就多等 1~3 秒，是「不流畅」的大头。
    private func harvestReplySentences() {
        guard !replySpeechCancelled, turnSentAt != .distantPast,
              let message = chatModel.messages.last(where: { $0.role == .assistant }),
              !message.failed, message.date >= turnSentAt else { return }
        if replyMessageID != message.id {
            replyMessageID = message.id
            replySpokenCount = 0
        }
        let text = message.text
        guard text.count > replySpokenCount else { return }
        let rest = String(text.dropFirst(replySpokenCount))
        let enders = "。！？!?…\n"
        guard let lastEnd = rest.lastIndex(where: { enders.contains($0) }) else { return }
        let chunk = String(rest[...lastEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunk.isEmpty else { return }
        speechQueue.append(chunk)
        replySpokenCount += rest.distance(from: rest.startIndex, to: lastEnd) + 1
    }

    /// 队列里有句子、嗓子和合成器都空着 → 念下一句
    private func pumpSpeechQueue() {
        guard !speechQueue.isEmpty, !isSpeaking, !voice.isPreparing else { return }
        let line = speechQueue.removeFirst()
        let text = CallScript.speakable(line, userName: callName)
        latestReply = text
        if lastTurnLatency == 0, turnSentAt != .distantPast {
            lastTurnLatency = Date().timeIntervalSince(turnSentAt)
        }
        voice.lineRateScale = Float.random(in: 0.96...1.04)
        voice.speak(text, for: character)
    }

    /// 角色说话时，判断用户是不是明显在抢话（电平兜底，文本判定在 handleRecognition 里）
    private func shouldYieldToUser() -> Bool {
        // 刚开口的前 0.5 秒先建立回声基线，别自己一说话就把自己掐了
        guard Date().timeIntervalSince(speechStartedAt) > 0.5 else { return false }
        let level = inputLevel
        echoBaseline = echoBaseline == 0 ? level : echoBaseline * 0.9 + level * 0.1
        // 两条路任一命中就算抢话：
        // ① 绝对够响 ② 明显压过当前漏音
        // 开了系统 AEC 后漏音本来就被压得很低，所以阈值要比之前敏感得多：
        // 旧实现「基线 × 2.2」在漏音一大时永远触发不了，这就是插不进话的直接原因。
        let absolute = level > 0.32
        let relative = level > 0.12 && level > echoBaseline * 1.3
        if absolute || relative {
            bargeFrames += 1
        } else {
            bargeFrames = max(0, bargeFrames - 1)
        }
        return bargeFrames >= 2
    }

    /// 识别回调：中间结果实时上屏；isFinal 或报错时先把已识别内容送出去，再交给 monitorLoop 续听
    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                // 角色正在说话时，识别是开着的：先把「自己的声音」过滤掉
                if isSpeaking {
                    let spokenLine = latestReply.isEmpty ? (voice.speakingText ?? "") : latestReply
                    if isEcho(text, spoken: spokenLine) {
                        return                      // 自说自话被识别进来，丢掉
                    }
                    // 用户真的开口了：立刻闭嘴，但保留已经识别到的内容继续收音
                    assumeUserIsTalking()
                }
                transcript = text
                lastResultAt = Date()
                lastVoiceTime = Date()
                didTryAlternate = false       // 识别正常，复位自愈计数
                asrFailCount = 0
                if statusNote.hasPrefix("听得") || statusNote.hasPrefix("换一种") {
                    statusNote = ""
                }
            }
            if result.isFinal {
                finishUtterance()
                return
            }
        }
        guard let error else { return }
        let ns = error as NSError
        // 1110 = 安静太久/系统自行断句，203/216/301 = 任务被系统收尾或打断。
        // 这些都不是故障——以前当错误处理，换识别方式 + 累计失败，
        // 两句话之后麦克风就彻底停了（表现：人物一直听不见）
        let benignCodes = [1110, 203, 216, 301]
        let benign = ns.domain == "kAFAssistantErrorDomain" && benignCodes.contains(ns.code)
        if benign {
            statusNote = ""
            finishUtterance(restartAfter: 0.3)
        } else if !didTryAlternate {
            // 真故障：换一种识别方式重试（每轮只换一次，避免来回抖）
            didTryAlternate = true
            asrMode = (asrMode == .server) ? .onDevice : .server
            finishUtterance(restartAfter: 0.8)
        } else {
            // 换过还是失败：退避重试（0.8s→1.6s→3.2s，上限 4s），永不放弃监听
            asrFailCount += 1
            statusNote = asrFailCount >= 3 ? "识别不稳定，正在自动重连…" : ""
            finishUtterance(restartAfter: min(4, 0.8 * Double(asrFailCount)))
        }
    }

    /// 收尾一句话：有内容就发；没内容就静默重开。
    /// 注意：这里**绝不能** stopEngine —— 静音超时（1110）是每分钟都会发生的正常事件，
    /// 以前每来一次就把整台麦克风引擎拆掉重建，中间那几秒用户说的话全丢，
    /// 表现就是「有时候怎么说话都识别不到」。
    private func finishUtterance(restartAfter delay: TimeInterval = 0) {
        recognitionEnded = true
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendTranscript()          // 内部会 stopRecognition 并发送
        } else {
            stopRecognition()         // 只结束这一轮识别，麦克风继续留在通话里
        }
        asrRestartAt = Date().addingTimeInterval(delay)
    }

    private func removeTapIfNeeded() {
        guard tapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func stopEngine() {
        stopRecognition()
        guard isEngineRunning else {
            removeTapIfNeeded()
            return
        }
        isEngineRunning = false
        audioEngine.stop()
        removeTapIfNeeded()
    }

    /// 拨号阶段就预申请权限（系统弹窗在响铃时出现，接通即可用）；
    /// 权限被拒不再递归重试，只在状态栏说清楚
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            Task { @MainActor in
                guard let self else { return }
                guard speechStatus == .authorized else {
                    self.statusNote = "语音识别权限未开启，TA 听不见你（设置 → 夜谈 → 语音识别）"
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    Task { @MainActor in
                        if granted {
                            self.statusNote = ""
                            // 只在已接通时直接开麦；拨号中交给接通后的 monitorLoop
                            if self.isConnected { self.beginRecording() }
                        } else {
                            self.statusNote = "麦克风权限未开启，TA 听不见你（设置 → 夜谈 → 麦克风）"
                        }
                    }
                }
            }
        }
    }

    /// 供外部（View 监听播放结束）刷新回声避让计时。
    /// 注意：这里绝不能重置 silenceStart —— TA 自己说完一句不算「用户开口了」，
    /// 否则冷场时间轴会被自己的碎碎念无限推后，永远走不到安慰和挂断。
    func touchActivity() {
        lastSpeakEnd = Date()
    }
}

/// 音频实时线程 ↔ 主线程之间传「当前识别请求」的小盒子。
/// tap 回调不在主线程，不能直接读 @MainActor 的 request 属性。
private final class SpeechRequestBox {
    var request: SFSpeechAudioBufferRecognitionRequest?
}

/// 引擎起不来时的内部错误（'what' 2003329396 之类的兜底）
private enum AudioEngineFailure: LocalizedError {
    case invalidInputFormat
    var errorDescription: String? { "麦克风输入格式异常" }
}

/// 简单 RMS 音量（0~1）
private extension AVAudioPCMBuffer {
    func rmsLevel() -> Float {
        guard let channel = floatChannelData, frameLength > 0 else { return 0 }
        let n = Int(frameLength)
        var sum: Float = 0
        for i in 0..<n {
            let v = channel.pointee[i]
            sum += v * v
        }
        let rms = sqrt(sum / Float(n))
        return min(1, rms * 6)
    }
}

// MARK: - 语音通话页（参考微信通话 UI：背景角色立绘 + 底部三圆钮）

struct VoiceCallView: View {
    let model: VoiceCallModel
    @ObservedObject private var voice = VoiceService.shared
    /// 长按通话计时可以开关诊断浮层（不用记启动参数）
    @State private var showDebug = VoiceCallModel.debugEnabled

    var body: some View {
        ZStack {
            backdrop
            shade

            VStack(spacing: 0) {
                // 顶部：最小化（贴住灵动岛下方）
                HStack {
                    Button {
                        CallCenter.shared.minimize()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                            Text("收起")
                                .font(Typo.body(12))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)

                // 现场数据：长按计时那一行可开关，调插话阈值就靠这几个数
                if showDebug {
                    Text(model.debugLine)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xFFD86B))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5), in: Capsule())
                        .padding(.top, 6)
                }

                Spacer(minLength: 0)

                // 中央：名字 / 计时 / 状态
                VStack(spacing: 8) {
                    Text(model.chatModel.character.name)
                        .font(Typo.display(23))
                        .tracking(5)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 4, y: 1)

                    Text(model.durationText)
                        .font(Typo.body(14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))
                        // 长按计时 0.8 秒：开关诊断浮层
                        .onLongPressGesture(minimumDuration: 0.8) {
                            withAnimation(.easeOut(duration: 0.2)) { showDebug.toggle() }
                        }

                    if model.isDialing || model.isThinking {
                        ThinkingDots()
                    } else if model.isListening {
                        Waveform(color: .white.opacity(0.9), animated: true)
                    }
                    Text(model.statusText)
                        .font(Typo.body(12.5))
                        .foregroundStyle(.white.opacity(0.62))
                }

                // 实时转写 / TA 刚说的话：垫一层半透明卡片，压住背景的盔甲和雨丝，
                // 否则字直接压在高对比画面上，读起来很费劲
                VStack(alignment: .leading, spacing: 9) {
                    if !model.transcript.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("你")
                                .font(Typo.body(10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                            Text(model.transcript)
                                .font(Typo.body(14))
                                .lineSpacing(3)
                                .foregroundStyle(.white.opacity(0.95))
                        }
                    }
                    // 念完也留一会儿：合成失败或戴耳机听不清时，至少还能看到 TA 说了什么
                    if !model.latestReply.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(model.chatModel.character.name)
                                .font(Typo.body(10, weight: .semibold))
                                .foregroundStyle(Palette.gold.opacity(0.95))
                            Text(model.latestReply)
                                .font(Typo.body(13))
                                .lineSpacing(3)
                                .foregroundStyle(.white.opacity(model.isSpeaking ? 0.92 : 0.62))
                                .lineLimit(4)
                                .animation(.easeOut(duration: 0.25), value: model.latestReply)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                // 底部三圆钮
                HStack(spacing: 0) {
                    callButton(
                        icon: model.isMicOn ? "mic.fill" : "mic.slash.fill",
                        label: model.isDialing ? "接通后自动开麦"
                             : (model.isMicOn ? "麦克风已开" : "麦克风已关"),
                        style: model.isMicOn ? .light : .dark,
                        pulse: model.isListening
                    ) {
                        model.toggleMic()
                    }

                    callButton(
                        icon: "phone.down.fill",
                        label: "挂断",
                        style: .danger
                    ) {
                        CallCenter.shared.end()
                    }

                    callButton(
                        icon: model.outputRouteIcon,
                        label: model.outputRouteName,
                        style: model.isSpeakerOn ? .light : .dark
                    ) {
                        model.toggleSpeaker()
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
            }
        }
        // 角色说完一句话 → 冷场计时重新起算
        .onReceive(voice.$speakingID) { id in
            if id == nil { model.touchActivity() }
        }
        // 冷场流程走完 → 结束整通电话（不只是收起页面）
        .onChange(of: model.shouldHangUp) { _, hangUp in
            if hangUp { CallCenter.shared.end() }
        }
    }

    // MARK: 背景

    private var backdrop: some View {
        GeometryReader { geo in
            AgentImage(name: model.chatModel.character.imageName,
                       hue: model.chatModel.character.hue,
                       saturation: model.chatModel.character.saturation)
                .frame(width: geo.size.width, height: geo.size.height)
                .livingGlow(intensity: 0.035)
                .clipped()
        }
        .ignoresSafeArea()
    }

    private var shade: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.bg.opacity(0.66), location: 0),
                .init(color: Palette.bg.opacity(0.22), location: 0.3),
                .init(color: Palette.bg.opacity(0.88), location: 0.75),
                .init(color: Palette.bg, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: 圆形按钮

    private enum CallButtonStyle {
        case light   // 白底黑图标（开启态）
        case dark    // 深底白图标（关闭态）
        case danger  // 红底（挂断）
    }

    private func callButton(icon: String, label: String,
                            style: CallButtonStyle, pulse: Bool = false,
                            action: @escaping () -> Void) -> some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(
                        style == .danger ? AnyShapeStyle(Color(hex: 0xE5484D))
                        : style == .light ? AnyShapeStyle(Color.white.opacity(0.92))
                        : AnyShapeStyle(Color.white.opacity(0.12))
                    )
                    .frame(width: 68, height: 68)
                    .overlay(
                        Circle().stroke(style == .light ? Color.clear : Palette.line2,
                                        lineWidth: style == .light ? 0 : 1)
                    )
                    .shadow(color: style == .danger ? Color(hex: 0xE5484D).opacity(0.4) : .black.opacity(0.35),
                            radius: 10, y: 5)
                    .overlay {
                        if pulse {
                            Circle()
                                .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                                .frame(width: 82, height: 82)
                                .breathingPulse()
                        }
                    }

                Image(systemName: icon)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(style == .light ? Color(hex: 0x14141C) : .white)
            }
            Text(label)
                .font(Typo.body(11))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityLabel(label)
    }
}

/// 最小化后的悬浮通话条（右上角小窗，点击回全屏；可继续使用 App 其他功能）
struct CallMiniBar: View {
    let model: VoiceCallModel

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                AgentImage(name: model.chatModel.character.imageName,
                           hue: model.chatModel.character.hue,
                           saturation: model.chatModel.character.saturation)
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                Circle()
                    .stroke(Palette.gold.opacity(0.55), lineWidth: 1)
                    .frame(width: 34, height: 34)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(model.chatModel.character.name)
                    .font(Typo.body(12, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(model.statusText)
                    .font(Typo.body(9.5))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
            }

            Text(model.durationText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.gold)
                .monospacedDigit()

            Button {
                CallCenter.shared.end()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .background(Color(hex: 0xE5484D), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("挂断")
            .accessibilityIdentifier("call.hangup")
        }
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Palette.line2, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
        .contentShape(Capsule())
        .onTapGesture { CallCenter.shared.expand() }
        .accessibilityLabel("返回通话")
    }
}

/// 思考中的三个点
private struct ThinkingDots: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 7, height: 7)
                    .opacity(on ? 1 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.55)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.18),
                        value: on
                    )
            }
        }
        .onAppear { on = true }
        .padding(.vertical, 3)
    }
}

/// 说话时的呼吸圆环
private struct BreathingPulse: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.12 : 0.96)
            .opacity(on ? 0.2 : 0.85)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

extension View {
    fileprivate func breathingPulse() -> some View { modifier(BreathingPulse()) }
}
