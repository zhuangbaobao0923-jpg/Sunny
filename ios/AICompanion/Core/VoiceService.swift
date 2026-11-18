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
        try? session.setCategory(.playAndRecord, mode: .voiceChat,
                                 options: [.allowBluetooth, .defaultToSpeaker])
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

    /// 正在合成音频（还没出声）——UI 据此显示「合成中…」，让等待可见
    @Published private(set) var isPreparing: Bool = false

    /// 当前实际使用的引擎，便于设置页展示
    @Published private(set) var lastEngine: String = "尚未播放"

    /// 本地服务是否可达（设置页展示）
    @Published private(set) var isLocalServerUp: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private let pitchedPlayer = PitchedAudioPlayer()
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]
    private var player: AVAudioPlayer?
    private var synthTask: Task<Void, Never>?
    /// 最近一次 speak() 的原文（用于气泡按钮高亮匹配）
    private var rawSpokenText: String?

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
    /// 引擎优先级：Mac 本地服务（14 音色最全）→ 云端（蜂窝可用）→ 设备内置（离线兜底）。
    func speak(_ rawText: String, for character: Character) {
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
        // 服务已知不可达时直接走云端，不再让用户干等网络超时
        guard isLocalServerUp else {
            startCloud(text, character: character)
            Task { _ = await probe() }        // 后台顺手复测，回到家后下一条自动回到 14 音色
            return
        }
        speakWithLocalEngine(text, character: character)
    }

    /// 云端链路：Azure 神经音色（用户选定的云扬等）优先，未配置或无额度过腾讯云
    private func startCloud(_ text: String, character: Character) {
        if AzureVoiceSettings.shared.isConfigured {
            speakWithAzure(text, character: character)
        } else {
            speakWithCloud(text, character: character)
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
        let playbackRate = explicitRate ?? character.voiceKind.cloudRate
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
        utterance.rate = character.voiceKind.rate
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
