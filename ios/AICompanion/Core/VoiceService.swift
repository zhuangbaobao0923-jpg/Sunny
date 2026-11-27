import AVFoundation
import Observation

// MARK: - 通话音频会话
//
// 通话时必须一直保持 .playAndRecord（否则麦克风拿不到音频），
// 但所有播放器以前都会把会话改成 .playback —— 角色一开口，识别就彻底哑掉，
// 表现就是「说了话没反应 / 一直正在聆听」。
// 统一从这里拿会话：通话中只激活不切类别，非通话才切 .playback。
enum CallAudioSession {
    /// 是否处于通话（由 VoiceCallModel 置位）
    nonisolated(unsafe) static var isActive = false

    /// 接通时调用：切成通话录音类别（免提 + 蓝牙）
    static func activate() {
        isActive = true
        let session = AVAudioSession.sharedInstance()
        // allowBluetooth：AirPods / 蓝牙耳机的通话通道（HFP）
        // allowBluetoothA2DP：只有 A2DP 的蓝牙音箱也能出声，否则这类设备在
        // playAndRecord 下根本没有可用输出，听起来就是「连了蓝牙没声音」
        try? session.setCategory(.playAndRecord, mode: .voiceChat,
                                 options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
        try? session.setActive(true)
    }

    /// 挂断时调用：恢复成普通播放
    static func deactivate() {
        isActive = false
        try? AVAudioSession.sharedInstance()
            .setCategory(.playback, options: [.duckOthers])
    }

    /// 播放前准备会话。通话中绝不改类别，只确保 active。
    static func prepareForPlayback() {
        let session = AVAudioSession.sharedInstance()
        if isActive {
            try? session.setActive(true)
        } else {
            try? session.setCategory(.playback, options: [.duckOthers])
            try? session.setActive(true)
        }
    }
}

/// 角色语音：优先使用本地 edge-tts 服务（Mac 上 127.0.0.1:9880，免费无 Key），
/// 服务未启动/合成失败时回退系统离线 TTS。不存在任何云端计费路径。
@MainActor
final class VoiceService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = VoiceService()

    /// 当前正在说话的角色 id（nil = 空闲）
    @Published private(set) var speakingID: String?

    /// 当前正在播放的台词原文（nil = 空闲；气泡播放按钮据此高亮/切换停止）
    @Published private(set) var speakingText: String?

    /// 最近一次合成失败原因（UI 可提示，不影响播放）
    @Published private(set) var lastError: String?

    /// 最近一次 Breeze 失败原因。兜底会清掉 lastError，这里单独留一份，便于设置页定位。
    @Published private(set) var lastBreezeError: String?

    /// 正在合成音频（还没出声）——UI 据此显示「合成中…」，让等待可见
    @Published private(set) var isPreparing: Bool = false

    /// 当前实际使用的引擎，便于设置页展示
    @Published private(set) var lastEngine: String = "尚未播放"

    /// 本地服务是否可达（设置页展示）
    @Published private(set) var isLocalServerUp: Bool = false

    /// 每句的播放语速微调（通话里用一个很小的随机值，避免每句都一模一样像播报）
    var lineRateScale: Float = 1

    private let synthesizer = AVSpeechSynthesizer()
    private let pitchedPlayer = PitchedAudioPlayer()
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]
    private var player: AVAudioPlayer?
    private var synthTask: Task<Void, Never>?
    /// 最近一次 speak() 的原文（用于气泡按钮高亮匹配）
    private var rawSpokenText: String?

    // ---- 预合成缓存 ----
    // 通话里一句接一句地念，如果每句都等云端合成（0.5~1.5s），
    // 句间的停顿就会又长又死板。这里在念上一句的时候就把下一句合成好。
    private struct CachedAudio {
        let url: URL
        let applyPitch: Bool
        let rate: Float?
    }
    private var audioCache: [String: CachedAudio] = [:]
    private var prefetchTasks: [String: Task<Void, Never>] = [:]

    // Breeze 流式播放
    private var breezeStream: BreezeStreamingRequest?
    private var breezePlayer: BreezeStreamPlayer?
    private var breezeToken: UUID?

    private override init() {
        super.init()
        synthesizer.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        // Bonjour 发现成功 → 立即用新地址重测，状态卡自动变绿
        TTSServiceDiscovery.shared.onFound = { [weak self] _ in
            self?.refreshServerStatus()
        }
        refreshServerStatus()
    }

    /// 探测本地服务状态：先让 Bonjour 自动发现（真机自动拿到 Mac IP），再做健康检查。
    /// 真机上「本地网络权限弹窗 + mDNS 发现」可能耗时较久，等待窗口给足 15 秒。
    func refreshServerStatus() {
        Task { [weak self] in
            guard let self else { return }
            let discovery = TTSServiceDiscovery.shared
            // idle = 首次；notFound = 上次超时，手动刷新时重新发现
            switch discovery.state {
            case .idle, .notFound: discovery.startBrowsing()
            default: break
            }
            // 首测当前地址（模拟器/已手输过 IP 的场景，立即成功）
            if await probe() { return }
            // 等待 Bonjour 发现更新地址（覆盖权限弹窗与 mDNS 延迟）
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(1.5))
                if await probe() { return }
            }
        }
    }

    private func probe() async -> Bool {
        do {
            try await VoiceSettings.shared.client.health()
            isLocalServerUp = true
            return true
        } catch {
            isLocalServerUp = false
            return false
        }
    }

    /// 朗读一段角色台词。动作描写（括号内）不会读出来。
    /// - Parameter allowBreeze: 仅“点语音条”这类用户主动播放为 true；自动朗读传 false，
    ///   避免每条回复都调用付费云端 TTS。
    /// 引擎优先级：聊天语音条 BreezeBlue → Mac 本地服务 → 云端（蜂窝可用）→ 设备内置（离线兜底）。
    func speak(_ rawText: String, for character: Character, allowBreeze: Bool = true) {
        stop()
        let text = Self.spokenPart(of: rawText)
        guard !text.isEmpty else {
            // 整句都是（动作描写）没有可读内容：必须复位状态，
            // 否则 isPreparing 卡住、通话页麦克风永远等不到「说完」信号
            rawSpokenText = nil
            speakingText = nil
            isPreparing = false
            return
        }
        rawSpokenText = rawText
        speakingText = rawText
        isPreparing = true
        // 聊天语音条与通话都优先走 Breeze：角色有专属音色、Key 已配。
        // 失败会自动回退本地/Azure/腾讯/系统，不会让通话哑掉。
        if allowBreeze,
           BreezeVoiceSettings.shared.isConfigured,
           let entry = BreezeVoiceCast.entry(for: character) {
            speakWithBreeze(text, character: character, entry: entry)
            return
        }
        // 命中预合成 → 直接播，省掉这一句的合成空档
        let key = cacheKey(text: text, character: character)
        if let cached = audioCache[key] {
            audioCache.removeValue(forKey: key)   // 用完即弃：临时文件可能被系统清理
            speakingID = character.id
            play(url: cached.url, text: text, character: character,
                 applyPitch: cached.applyPitch, rate: cached.rate)
            return
        }
        // 服务已知不可达时直接走云端，不再让用户干等网络超时
        guard isLocalServerUp else {
            startCloud(text, character: character)
            Task { _ = await probe() }        // 后台顺手复测，回到家后下一条自动回到 14 音色
            return
        }
        speakWithLocalEngine(text, character: character)
    }

    /// 预合成下一句：只写缓存，不动 speakingID / isPreparing，不会打断正在播的句子。
    /// 通话的碎碎念就是靠这个把「等合成」的空档抹掉的。
    func prepare(_ rawText: String, for character: Character) {
        let text = Self.spokenPart(of: rawText)
        guard !text.isEmpty else { return }
        // Breeze 走流式，旧引擎的预合成用不上，别白跑
        if BreezeVoiceSettings.shared.isConfigured,
           BreezeVoiceCast.entry(for: character) != nil {
            return
        }
        let key = cacheKey(text: text, character: character)
        guard audioCache[key] == nil, prefetchTasks[key] == nil else { return }
        let kind = character.voiceKind
        let engine = engineTag()

        prefetchTasks[key] = Task { [weak self] in
            guard let self else { return }
            defer { self.prefetchTasks[key] = nil }
            do {
                let entry: CachedAudio
                switch engine {
                case "local":
                    let url = try await LocalTTSAudioCache.shared.audioURL(
                        text: text, voice: kind.edgeVoice, rate: kind.edgeRate,
                        pitch: kind.edgePitch, client: VoiceSettings.shared.client
                    )
                    entry = CachedAudio(url: url, applyPitch: true, rate: 1.0)
                case "azure":
                    let url = try await AzureTTSClient.synthesize(text: text, kind: kind)
                    entry = CachedAudio(url: url, applyPitch: false, rate: nil)
                default:
                    let url = try await TencentTTSClient.synthesize(text: text, kind: kind)
                    entry = CachedAudio(url: url, applyPitch: true, rate: nil)
                }
                if self.audioCache.count > 60 { self.audioCache.removeAll() }
                self.audioCache[key] = entry
            } catch {
                // 预合成失败不打扰用户：真正播到这一句时会再合成一次
            }
        }
    }

    private func engineTag() -> String {
        if isLocalServerUp { return "local" }
        if AzureVoiceSettings.shared.isConfigured { return "azure" }
        return "tencent"
    }

    private func cacheKey(text: String, character: Character) -> String {
        "\(engineTag())|\(character.voiceKind.rawValue)|\(text)"
    }

    /// 云端链路：Azure 神经音色（用户选定的云扬等）优先，未配置或无额度过腾讯云
    private func startCloud(_ text: String, character: Character) {
        if AzureVoiceSettings.shared.isConfigured {
            speakWithAzure(text, character: character)
        } else {
            speakWithCloud(text, character: character)
        }
    }

    // MARK: - BreezeBlue 角色音色（聊天语音条）

    private func speakWithBreeze(_ text: String, character: Character, entry: BreezeVoiceCast.Entry) {
        speakingID = character.id
        lastEngine = "BreezeBlue · \(entry.name)"
        lastError = nil
        lastBreezeError = nil

        // 命中缓存：第二次点同一条直接播，不再请求、不再计费
        if let cached = BreezeTTSClient.cachedAudio(text: text, entry: entry) {
            play(url: cached, text: text, character: character, applyPitch: false, rate: 1.0)
            return
        }

        guard let player = BreezeStreamPlayer() else {
            fallbackFromBreeze(text: text, character: character, error: "流式播放器初始化失败")
            return
        }

        let token = UUID()
        breezeToken = token

        do {
            try player.start(onStart: { [weak self] in
                guard let self, self.breezeToken == token else { return }
                self.isPreparing = false
            }, onFinish: { [weak self] in
                guard let self, self.breezeToken == token else { return }
                self.breezeStream = nil
                self.breezePlayer = nil
                self.breezeToken = nil
                if self.speakingID == character.id {
                    self.speakingID = nil
                    self.speakingText = nil
                }
            })
        } catch {
            fallbackFromBreeze(text: text, character: character, error: error.localizedDescription)
            return
        }

        let request: URLRequest
        do {
            request = try BreezeTTSClient.makeStreamRequest(text: text, entry: entry)
        } catch {
            player.stop()
            fallbackFromBreeze(text: text, character: character, error: error.localizedDescription)
            return
        }

        breezePlayer = player
        var pcm = Data()

        breezeStream = BreezeStreamingRequest(request: request, onData: { data in
            DispatchQueue.main.async {
                guard self.breezeToken == token else { return }
                pcm.append(data)
                player.append(data)
            }
        }, onComplete: { error in
            DispatchQueue.main.async {
                guard self.breezeToken == token else { return }
                self.breezeStream = nil

                if let error {
                    self.lastBreezeError = error.localizedDescription
                    if pcm.isEmpty {
                        // 一个字都没出：静默回退到原有链路
                        player.stop()
                        self.breezePlayer = nil
                        self.breezeToken = nil
                        self.fallbackFromBreeze(
                            text: text,
                            character: character,
                            error: error.localizedDescription
                        )
                    } else {
                        // 已经出声：让已缓冲的部分播完，不再追第二条
                        player.finish()
                        BreezeTTSClient.saveWAV(pcm: pcm, text: text, entry: entry)
                    }
                } else {
                    player.finish()
                    BreezeTTSClient.saveWAV(pcm: pcm, text: text, entry: entry)
                }
            }
        })
    }

    private func fallbackFromBreeze(text: String, character: Character, error: String) {
        lastBreezeError = error
        lastError = error
        breezeStream?.cancel()
        breezeStream = nil
        breezePlayer?.stop()
        breezePlayer = nil
        breezeToken = nil
        isPreparing = false

        if isLocalServerUp {
            speakWithLocalEngine(text, character: character)
        } else {
            startCloud(text, character: character)
        }
    }

    // MARK: - Azure 神经语音（云扬，最贴人设）

    private func speakWithAzure(_ text: String, character: Character) {
        speakingID = character.id
        lastEngine = "云端语音 · 云扬"
        lastError = nil
        let kind = character.voiceKind

        synthTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await AzureTTSClient.synthesize(text: text, kind: kind)
                try Task.checkCancellation()
                await MainActor.run {
                    guard self.speakingID == character.id else { return }
                    // Azure 已在 SSML 里做好了音高/语速，播放时不再二次变调
                    self.play(url: url, text: text, character: character, applyPitch: false)
                }
            } catch is CancellationError {
                // 用户切走，静默
                self.isPreparing = false
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.speakWithCloud(text, character: character)
                }
            }
        }
    }

    func stop() {
        synthTask?.cancel()
        synthTask = nil
        breezeToken = nil
        breezeStream?.cancel()
        breezeStream = nil
        breezePlayer?.stop()
        breezePlayer = nil
        player?.stop()
        player = nil
        pitchedPlayer.stop()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakingID = nil
        speakingText = nil
        isPreparing = false
    }

    func toggle(_ rawText: String, for character: Character) {
        if speakingID == character.id {
            stop()
        } else {
            speak(rawText, for: character)
        }
    }

    /// 去掉（…）动作描写与空白（纯字符串处理，无需主线程）
    nonisolated static func spokenPart(of text: String) -> String {
        text.replacingOccurrences(
            of: "（[^）]*）|\\([^)]*\\)",
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 本地引擎（edge-tts，免费）

    private func speakWithLocalEngine(_ text: String, character: Character) {
        speakingID = character.id
        lastEngine = "本地语音 · \(character.voiceKind.edgeVoice)"
        lastError = nil
        let kind = character.voiceKind

        synthTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await LocalTTSAudioCache.shared.audioURL(
                    text: text,
                    voice: kind.edgeVoice,
                    rate: kind.edgeRate,
                    pitch: kind.edgePitch,
                    client: VoiceSettings.shared.client
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard self.speakingID == character.id else { return }
                    self.isLocalServerUp = true
                    // 本地 edge-tts 的语速已在合成阶段（edgeRate）确定，播放端不能再乘 cloudRate
                    self.play(url: url, text: text, character: character, rate: 1.0)
                }
            } catch is CancellationError {
                // 用户切走/停止，静默
                self.isPreparing = false
            } catch {
                await MainActor.run {
                    self.isLocalServerUp = false
                    self.startCloud(text, character: character)
                }
            }
        }
    }

    // MARK: - 云端引擎（腾讯云语音合成，蜂窝数据可用）

    private func speakWithCloud(_ text: String, character: Character) {
        speakingID = character.id
        lastEngine = "云端语音 · \(character.voiceKind.rawValue)"
        lastError = nil
        let kind = character.voiceKind

        synthTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await TencentTTSClient.synthesize(text: text, kind: kind)
                try Task.checkCancellation()
                await MainActor.run {
                    guard self.speakingID == character.id else { return }
                    self.play(url: url, text: text, character: character)
                }
            } catch is CancellationError {
                // 用户切走，静默
                self.isPreparing = false
            } catch {
                await MainActor.run {
                    self.lastEngine = "设备内置语音（云端与本地服务均不可用）"
                    self.lastError = error.localizedDescription
                    self.speakWithSystem(text, character: character)
                }
            }
        }
    }

    /// - Parameter rate: 播放倍速；nil = 按音色实测值归一（cloudRate），本地合成传 1.0
    private func play(url: URL, text: String, character: Character,
                      applyPitch: Bool = true, rate explicitRate: Float? = nil) {
        // 语速微调只改时间不改音高：每句 ±4% 的变化足够打散「播报感」
        let baseRate = explicitRate ?? character.voiceKind.cloudRate
        let playbackRate = min(2.0, max(0.5, baseRate * lineRateScale))
        // 需要变调的角色走 AVAudioEngine（实时降调 + 压语速），其余走原生播放
        let cents = applyPitch ? character.voiceKind.cloudPitchCents : 0
        if cents != 0 {
            pitchedPlayer.onFinish = { [weak self] in
                self?.speakingID = nil
                self?.speakingText = nil
            }
            do {
                try pitchedPlayer.play(
                    url: url,
                    cents: cents,
                    rate: playbackRate
                )
                isPreparing = false
                return
            } catch {
                lastError = "变调播放失败，改用原声：\(error.localizedDescription)"
            }
        }
        do {
            // 真机上必须先激活音频会话，否则首次播放静默无声。
            // 通话中这里只激活、不切 .playback，否则麦克风立刻失效。
            CallAudioSession.prepareForPlayback()
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            // 语速归一只改时间不改音高（AVAudioPlayer 的 enableRate 是时间拉伸）
            let rate = playbackRate
            if rate != 1.0 {
                player.enableRate = true
                player.rate = max(0.5, min(2.0, rate))
            }
            player.prepareToPlay()
            guard player.play() else {
                lastError = "音频播放启动失败"
                speakWithSystem(text, character: character)
                return
            }
            self.player = player
            isPreparing = false
        } catch {
            lastError = "音频播放失败：\(error.localizedDescription)"
            speakWithSystem(text, character: character)
        }
    }

    // MARK: - 设备内置语音（离线兜底，永远可用）

    private func speakWithSystem(_ text: String, character: Character) {
        player?.stop()
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        lastEngine = "设备内置语音（离线）"

        // 真机上必须先激活音频会话，否则可能静默无声
        CallAudioSession.prepareForPlayback()

        let selected = voice(for: character)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selected
        utterance.pitchMultiplier = Self.systemPitch(for: character.voiceKind, voice: selected)
        utterance.rate = min(1.0, max(0.4, character.voiceKind.rate * lineRateScale))
        utterance.postUtteranceDelay = 0.1
        utterance.volume = 1.0

        speakingID = character.id
        isPreparing = false
        synthesizer.speak(utterance)
    }

    /// 内置语音的音调：挑到男声就自然念，只有拿女声顶男角色时才压低
    private static func systemPitch(for kind: VoiceKind, voice: AVSpeechSynthesisVoice?) -> Float {
        let isMaleRole = kind.gender == "男"
        let maleVoice = SystemVoiceCatalog.isMaleVoice(voice)
        switch (isMaleRole, maleVoice) {
        case (true, true):
            return 0.95
        case (true, false):
            return kind == .magneticMale ? 0.76 : 0.82
        default:
            return min(1.25, max(0.92, kind.pitch))
        }
    }

    private func voice(for character: Character) -> AVSpeechSynthesisVoice? {
        let key = character.voiceKind.rawValue
        if let cached = voiceCache[key] { return cached }
        let selected = SystemVoiceCatalog.best(for: character.voiceKind)
        if let selected {
            voiceCache[key] = selected
        }
        return selected
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.speakingID = nil
            self?.speakingText = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.speakingID = nil
            self?.speakingText = nil
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.speakingID = nil
            self?.speakingText = nil
            self?.player = nil
        }
    }
}
