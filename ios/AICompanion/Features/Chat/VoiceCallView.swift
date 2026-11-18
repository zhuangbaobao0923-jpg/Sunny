import SwiftUI
import Speech
import AVFoundation

// MARK: - 语音通话模型
// 点【通话】→ 回铃音拨号约 20 秒（4 声）→ 对方接通 → 麦克风常开、静音 1.6s 自动断句发送
// → 角色按人设回复并朗读；朗读时自动让出麦克风（防回声）；60 秒冷场主动关怀。
// 自愈能力：端上识别失效自动切联网识别 / 合成卡死 15s 强制复位 / 回复期间说的话不丢 / 错误上屏。

/// 通话阶段：拨号中（只听回铃音）→ 已接通（开始收音与计时）
enum CallPhase { case dialing, connected }

@MainActor
@Observable
final class VoiceCallModel {
    private(set) var phase: CallPhase = .dialing
    private(set) var isMicOn = true          // 默认开麦
    private(set) var isSpeakerOn = true      // 默认免提
    private(set) var isEngineRunning = false // 识别引擎是否在收音
    private(set) var transcript = ""         // 用户正在说的话（实时转写）
    private(set) var duration = 0            // 通话秒数（接通后才开始计）
    private(set) var statusNote = ""         // 权限/异常提示
    private(set) var latestReply = ""        // AI 最近一条回复
    private(set) var inputLevel: Double = 0  // 实时音量 0~1（UI 波形用）
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
    private var lastActivity = Date()        // 最近一次有效互动（说话/回复完）
    private var lastSpeakEnd = Date.distantPast  // 角色说完话的时刻（防回声）

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// 麦克风 tap 是否已装（装过没拆就再装会直接崩，必须自己记账）
    private var tapInstalled = false

    // ---- 识别自愈 ----
    /// 识别方式。默认走系统识别（联网，最稳）；端上识别在 zh-CN 上经常
    /// supportsOnDeviceRecognition=true 但模型缺失，静默无结果，只在联网失败后才尝试。
    private enum ASRMode { case server, onDevice }
    private var asrMode: ASRMode = .server
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

    private static let silenceSendDelay: TimeInterval = 1.6
    private static let ringDuration: TimeInterval = 20          // 拨号回铃音时长（4 声）
    private static let coldPromptAfter: TimeInterval = 30      // 打完招呼 30 秒没人说话 → 角色先开口
    private static let chatterInterval: TimeInterval = 14      // 碎碎念间隔
    private static let chatterDuration: TimeInterval = 300     // 碎碎念持续 5 分钟
    private static let farewell = "不想说话也没关系，我就陪你待一会儿，等你什么时候想说可以随时给我打电话。"

    /// 冷场推进：normal → chattering（30s 后开始，按角色话术轮播）→ closing（告别后挂断）
    private enum ColdStage { case normal, prompted, chattering, closing }
    private var coldStage: ColdStage = .normal
    private var chatterStart: Date?
    private var lastChatterAt: Date = .distantPast
    private var chatterIndex = 0
    private var chatterPool: [String] = VoiceCallModel.defaultChatter

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
        // AI 回合结束 → 用角色声音朗读
        chatModel.onReplyFinished = { [weak self] reply in
            guard let self else { return }
            self.latestReply = reply
            self.voice.speak(reply, for: self.character)
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
        lastActivity = Date()
        resetColdFlow()
        prepareChatter()

        // 权限预检：缺权限现在就弹/就提示，别等接通后才发现听不见
        let speechOK = SFSpeechRecognizer.authorizationStatus() == .authorized
        let micOK = AVAudioSession.sharedInstance().recordPermission == .granted
        if !speechOK || !micOK { requestPermissions() }

        ringback.start()
        ringTask = Task { [weak self] in
            // 20 秒 = 4 个完整铃声周期（响 1 停 4），像真的在等对方接
            try? await Task.sleep(for: .seconds(Self.ringDuration))
            guard let self, !Task.isCancelled else { return }
            self.connect()
        }
    }

    /// 对方接听：停回铃音 → 开始计时 → 角色开口 → 开麦监听
    private func connect() {
        guard phase == .dialing else { return }
        ringTask = nil
        ringback.stop()
        phase = .connected
        duration = 0
        lastActivity = Date()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.duration += 1 }
        }

        // 接通先把音频会话锁到「通话」类别：喇叭外放 + 麦克风同时可用。
        // 不锁的话，角色一开口（TTS 走 .playback）麦克风就被系统切断，之后只会「正在聆听」
        CallAudioSession.activate()
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)

        // 角色接通：用「电话味」的专属招呼语喊用户昵称（不是聊天开场白）
        let greeting = CallScript.greeting(for: character, userName: userName)
        chatModel.appendCallGreeting(greeting)
        voice.speak(greeting, for: character)
        monitorTask = monitorLoop()
    }

    func hangUp() {
        ringTask?.cancel()
        ringTask = nil
        ringback.stop()
        monitorTask?.cancel()
        monitorTask = nil
        timer?.invalidate()
        timer = nil
        stopEngine()
        voice.stop()
        chatModel.onReplyFinished = nil
        CallAudioSession.deactivate()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: 底部三按钮

    func toggleMic() {
        isMicOn.toggle()
        statusNote = ""
        // 拨号中不开麦：还没接通，麦克风不该工作
        if isMicOn, isConnected {
            lastActivity = Date()
            beginRecording()
        } else if !isMicOn {
            transcript = ""
            stopEngine()
        }
    }

    func toggleSpeaker() {
        isSpeakerOn.toggle()
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
    }

    // MARK: 常驻监控：回声避让 / 自动断句 / 冷场关怀 / 断线自愈

    private func monitorLoop() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                guard let self else { return }
                // 合成卡死看门狗：4G 下本地服务超时+云端重试可能把 isPreparing 拖住，
                // speakingID 一直占用会让麦克风永不恢复（表现：只播招呼语，之后装聋）
                if self.voice.isPreparing {
                    if self.prepareSince == nil { self.prepareSince = Date() }
                    if Date().timeIntervalSince(self.prepareSince!) > 15 {
                        self.voice.stop()
                        self.prepareSince = nil
                        self.statusNote = "语音合成超时，已重置，请再说一遍"
                    }
                } else {
                    self.prepareSince = nil
                }
                // 角色说话时让出麦克风（防止扬声器声音被识别成用户的话）
                if self.isSpeaking {
                    self.stopEngine()
                    continue
                }
                // 回复出完 → 补发流式期间用户说的话（原实现直接丢弃）
                if !self.isThinking, !self.isSpeaking, let pending = self.pendingSend {
                    self.pendingSend = nil
                    self.lastActivity = Date()
                    self.chatModel.input = pending
                    self.chatModel.send()
                }
                // 麦克风开着但引擎停了（刚播完/刚发送完/识别任务已结束）→ 稍等回声散去再恢复监听；
                // 失败退避期间（asrRestartAt）先不重开
                if self.isMicOn, !self.isThinking,
                   Date().timeIntervalSince(self.lastSpeakEnd) > 0.6,
                   Date() >= self.asrRestartAt {
                    // 识别任务正常收尾（isFinal）后引擎可能还在跑空转 → 先收干净再重开
                    if self.recognitionEnded, self.isEngineRunning {
                        self.stopEngine()
                    }
                    if !self.isEngineRunning {
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
                        self.stopEngine()
                        self.asrRestartAt = Date().addingTimeInterval(1.5)
                        continue
                    }
                    // 有人声、有音频，12 秒却一个字都没出来 → 换识别方式试一次
                    if self.bufferCount > 8, elapsed > 12,
                       Date().timeIntervalSince(self.lastResultAt) > 12 {
                        if !self.didTryAlternate {
                            self.didTryAlternate = true
                            self.asrMode = (self.asrMode == .server) ? .onDevice : .server
                            self.statusNote = "换一种识别方式再试…"
                            self.stopEngine()
                            self.asrRestartAt = Date().addingTimeInterval(0.8)
                        } else if elapsed > 30 {
                            // 端上识别经常「一声不响」（模型缺失也不报错），
                            // 不能死守一种方式：满 30 秒换回另一种，并重新给一次机会
                            self.asrFailCount += 1
                            self.asrMode = (self.asrMode == .server) ? .onDevice : .server
                            self.didTryAlternate = false
                            self.statusNote = "识别不太顺，正在换一种方式…"
                            self.stopEngine()
                            self.asrRestartAt = Date().addingTimeInterval(min(4, 0.8 * Double(self.asrFailCount)))
                        }
                        continue
                    }
                }
                // 说完一段话：转写非空且静音超过 1.6s → 自动发送
                if self.isEngineRunning,
                   !self.transcript.isEmpty,
                   Date().timeIntervalSince(self.lastVoiceTime) > Self.silenceSendDelay {
                    self.sendTranscript()
                    continue
                }
                // 冷场流程：问一句 → 碎碎念 5 分钟 → 告别 → 自动挂断
                if self.isMicOn, !self.isThinking, self.transcript.isEmpty {
                    let idle = Date().timeIntervalSince(self.lastActivity)

                    if self.coldStage == .closing {
                        // 告别那句已经播完 → 挂断
                        if !self.isSpeaking, Date().timeIntervalSince(self.lastActivity) > 0.8 {
                            self.finishAutoHangUp()
                            return
                        }
                    } else if self.coldStage == .normal || self.coldStage == .prompted {
                        // 打完招呼 30 秒没人说话 → 直接进入角色专属碎碎念（不再先丢一句通用问话）
                        if idle > Self.coldPromptAfter {
                            self.coldStage = .chattering
                            self.chatterStart = Date()
                            self.chatterIndex = 0
                            self.lastChatterAt = .distantPast   // 立即说第一句
                        }
                    } else if self.coldStage == .chattering {
                        let elapsed = Date().timeIntervalSince(self.chatterStart ?? Date())
                        if elapsed >= Self.chatterDuration {
                            self.coldStage = .closing
                            self.lastActivity = Date()
                            self.voice.speak(Self.farewell, for: self.character)
                        } else if Date().timeIntervalSince(self.lastChatterAt) > Self.chatterInterval {
                            self.speakChatter()
                        }
                    }
                }
            }
        }
    }

    private func sendTranscript() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = ""
        stopEngine()
        lastActivity = Date()
        resetColdFlow()                     // 用户开口了，冷场流程作废
        statusNote = ""
        // 过滤纯标点/空白；「嗯」「在」这类单字是真实回答，不能再丢
        let meaningful = text.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0) || $0.value > 0x2E80
        }
        guard meaningful else { return }

        // 上一条还在回复中：暂存，回复结束后由 monitorLoop 补发（原实现直接丢弃）
        guard !chatModel.isStreaming else {
            pendingSend = text
            return
        }
        chatModel.input = text
        chatModel.send()
    }

    // MARK: 冷场流程

    private func resetColdFlow() {
        coldStage = .normal
        chatterStart = nil
        chatterIndex = 0
        lastChatterAt = .distantPast
    }

    /// 说一句碎碎念（按池轮转，不重复、不中断）
    private func speakChatter() {
        guard !chatterPool.isEmpty else { return }
        let line = chatterPool[chatterIndex % chatterPool.count]
        chatterIndex += 1
        lastChatterAt = Date()
        voice.speak(line, for: character)
    }

    /// 模型可用时，用角色口吻生成一批碎碎念追加在后（更贴人设）；
    /// 分角色专属话术排在前面并打乱顺序 —— 每个人物说的话都不一样，同一个人每次顺序也不同
    private func prepareChatter() {
        chatterPool = CallScript.chatter(for: character).shuffled()
        guard LLMSettings.shared.isReady else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let lines = try? await Self.generateChatter(for: self.character), !lines.isEmpty else { return }
            self.chatterPool += lines.shuffled()   // 追加在后：先保证角色专属，再用模型补充
        }
    }

    private static func generateChatter(for character: Character) async throws -> [String] {
        let system = PersonaPrompt.system(for: character, level: 4, memory: [])
        let user = """
        对方在通话中突然沉默，很久不说话。你担心但不想逼问，只是一声声地小声念叨、自己跟自己说话，把关心说出来。
        写 8 句你会独自说出口的话：第一人称，语气和你的性格一致，每句 10~30 字，像自言自语。
        要求：意思各不相同，不要连续质问，不要提 AI/模型，不要 Markdown，不要编号。
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
                return s.trimmingCharacters(in: .whitespaces)
            }
            .filter { $0.count >= 6 && $0.count <= 80 }
            .prefix(8)
            .map { $0 }
    }

    /// 告别说完 → 挂断
    private func finishAutoHangUp() {
        hangUp()
        shouldHangUp = true
    }

    // MARK: 语音识别

    /// 开麦：一次只建一条识别任务；任务结束（isFinal / 报错）由 monitorLoop 续听。
    /// 关键修复：识别任务结束后引擎会空转（系统早已收尾），旧代码没处理 isFinal，
    /// 于是界面永远停在「正在聆听」——这就是「说两句话就没动静」的根因。
    private func beginRecording() {
        guard !isEngineRunning, isMicOn, isConnected else { return }

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
            // 通话中永远保持 .playAndRecord：这是麦克风能被听见的前提
            CallAudioSession.activate()
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true)
            try session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            request.addsPunctuation = true
            // 默认联网识别（最稳）；只有联网失败后才换端上
            if asrMode == .onDevice, recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request
            engineStartedAt = Date()
            lastResultAt = Date()
            bufferCount = 0
            transcript = ""
            recognitionEnded = false

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                statusNote = "麦克风不可用（可能被其他 App 占用）"
                asrRestartAt = Date().addingTimeInterval(1.5)
                return
            }
            removeTapIfNeeded()
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self, weak request] buffer, _ in
                request?.append(buffer)
                let level = buffer.rmsLevel()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.bufferCount += 1
                    self.inputLevel = Double(level)
                    if level > 0.06 { self.lastVoiceTime = Date() }
                }
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()

            isEngineRunning = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    self?.handleRecognition(result: result, error: error)
                }
            }
            if task == nil {
                // recognizer 拒绝建任务：收拾干净，稍后重试
                stopEngine()
                statusNote = "识别服务暂时不可用，正在重连…"
                asrRestartAt = Date().addingTimeInterval(1.2)
            }
        } catch {
            removeTapIfNeeded()
            isEngineRunning = false
            statusNote = "无法启动麦克风：\(error.localizedDescription)"
            asrRestartAt = Date().addingTimeInterval(1.0)
        }
    }

    /// 识别回调：中间结果实时上屏；isFinal 或报错时先把已识别内容送出去，再交给 monitorLoop 续听
    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
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

    /// 收尾一句话：有内容就发；没内容就静默重开
    private func finishUtterance(restartAfter delay: TimeInterval = 0) {
        recognitionEnded = true
        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendTranscript()          // 内部会 stopEngine 并发送
        } else {
            stopEngine()
        }
        asrRestartAt = Date().addingTimeInterval(delay)
    }

    private func removeTapIfNeeded() {
        guard tapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func stopEngine() {
        guard isEngineRunning else {
            removeTapIfNeeded()
            return
        }
        isEngineRunning = false
        audioEngine.stop()
        removeTapIfNeeded()
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        transcript = ""
        inputLevel = 0
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

    /// 供外部（View 监听播放结束）刷新冷场计时；冷场流程已启动时不再刷新
    func touchActivity() {
        lastSpeakEnd = Date()
        if coldStage == .normal {
            lastActivity = Date()
        }
    }
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

                    if model.isDialing || model.isThinking {
                        ThinkingDots()
                    } else if model.isListening {
                        Waveform(color: .white.opacity(0.9), animated: true)
                    }
                    Text(model.statusText)
                        .font(Typo.body(12.5))
                        .foregroundStyle(.white.opacity(0.62))
                }

                // 实时转写 / 正在朗读的回复
                VStack(alignment: .leading, spacing: 10) {
                    if !model.transcript.isEmpty {
                        Text(model.transcript)
                            .font(Typo.body(14))
                            .lineSpacing(4)
                            .foregroundStyle(.white)
                    }
                    if model.isSpeaking, !model.latestReply.isEmpty {
                        Text(model.latestReply)
                            .font(Typo.body(13))
                            .lineSpacing(4)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(4)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                // 底部三圆钮
                HStack(spacing: 0) {
                    callButton(
                        icon: model.isMicOn ? "mic.fill" : "mic.slash.fill",
                        label: model.isDialing ? "接通后自动开麦"
                             : (model.isMicOn ? "麦克风已开" : "麦克风已关"),
                        style: model.isMicOn ? .light : .dark,
                        pulse: model.isListening && model.inputLevel > 0.12
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
                        icon: model.isSpeakerOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        label: model.isSpeakerOn ? "扬声器已开" : "扬声器已关",
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
            .accessibilityLabel("挂断")
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
