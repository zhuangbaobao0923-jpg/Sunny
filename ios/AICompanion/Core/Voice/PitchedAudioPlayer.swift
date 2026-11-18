import AVFoundation

/// 带变调的音频播放器。
/// 云端音色（腾讯云基础音色）天生偏“播音腔”，在手机端实时把音高降低、语速压慢，
/// 就能得到低沉稳重的质地——不需要额外付费音色，也不需要重新合成。
final class PitchedAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioNodeHolder.node()
    private let timePitch = AVAudioUnitTimePitch()
    private var playing = false
    /// 监听真实播放结束的后台任务
    private var monitorTask: Task<Void, Never>?

    /// 播放自然结束（被 stop() 打断不回调）
    var onFinish: (() -> Void)?

    init() {
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
    }

    /// cents：音高变化（-1200 = 降一个八度）；rate：语速倍数（1 = 不变）
    func play(url: URL, cents: Float, rate: Float) throws {
        stop()
        let file = try AVAudioFile(forReading: url)
        // 通话中保持 .playAndRecord，避免把识别引擎的麦克风链路切走
        CallAudioSession.prepareForPlayback()

        timePitch.pitch = cents
        timePitch.rate = max(0.5, min(2.0, rate))

        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        playing = true

        // 注意：scheduleFile 的 completionHandler 在「调度完成」时触发（几乎立即），
        // 不是播放结束——之前用它回调 onFinish，导致角色刚开口就被判定说完，
        // 通话页随即启动麦克风引擎把播放打断（话被截断 + 回声误识别）。
        // 改为按音频真实时长等待，再轮询 isPlaying 确认真正播完。
        let seconds = Double(file.length) / file.processingFormat.sampleRate / Double(max(0.5, min(2.0, rate)))
        player.scheduleFile(file, at: nil)
        player.play()

        let effect = onFinish
        monitorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds + 0.25))
            while let self, self.playing, self.player.isPlaying {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard let self, self.playing else { return }
            self.playing = false
            await MainActor.run { effect?() }
        }
    }

    func stop() {
        playing = false
        monitorTask?.cancel()
        monitorTask = nil
        player.stop()
        if engine.isRunning { engine.pause() }
    }
}

/// AVAudioPlayerNode 的构造包装（避免在属性初始化里重复写）
private enum AVAudioNodeHolder {
    static func node() -> AVAudioPlayerNode { AVAudioPlayerNode() }
}

// MARK: - 角色音色的手机端变调参数

extension VoiceKind {
    /// 云端音色播放时的音高偏移（cents，-1200 = 降一个八度）。
    /// 重要：腾讯云精品音色是 16kHz 音源，端上降 3~4 个半音会把声音拖成
    /// 发闷、带金属味的「怪声」——这是之前音色难听的主因之一。
    /// 低沉质感改为直接选低基频音色（如 101021 智瑞 105Hz）实现，这里一律不降调。
    var cloudPitchCents: Float {
        switch self {
        case .deepMale: return 0
        case .magneticMale: return 0
        case .clearYoungMale: return 0
        case .sunnyMale: return 0
        case .broadcastMale: return 0
        case .boyish: return 0
        case .cartoonBoy: return 0
        case .sweetGirl: return 0
        default: return 0
        }
    }

    /// 云端音色播放语速倍数（1 = 原速）。
    ///
    /// 各音色的**原始**语速差得很远（同一句 32 字，Speed=0 实测）：
    /// 智柯 5.52 字/秒、智华 5.48、智希 4.79、智瑞 4.90、极低男声 5.27、智辉 4.84、
    /// 智云 4.73、智瑜 4.66、智甜 4.25……
    /// 旧版还按「人设气质」再乘 -20%/+20%，结果沉金男声只剩 3.9 字/秒（太慢），
    /// 少年音飙到 6.6 字/秒（太快）。现在统一按实测值归一到 4.8 字/秒 ≈ 正常人说话。
    var cloudRate: Float {
        switch self {
        case .sunnyMale: return 1.01      // 4.73 → 4.78
        case .clearYoungMale: return 0.87 // 5.52 → 4.80
        case .deepMale: return 0.98       // 4.90 → 4.80
        case .magneticMale: return 0.91   // 5.27 → 4.80
        case .broadcastMale: return 0.99  // 4.84 → 4.79
        case .boyish: return 0.88         // 5.48 → 4.82
        case .warmFemale: return 1.03     // 4.66 → 4.80
        case .livelyGirl: return 1.00     // 4.79
        case .softGirl: return 1.06       // 4.53 → 4.80
        case .elegantFemale: return 1.01  // 4.73 → 4.78
        case .cartoonBoy: return 0.97     // 4.93 → 4.78
        case .sweetGirl: return 1.13      // 4.25 → 4.80
        case .dongbeiAunt: return 1.03    // 4.68 → 4.82
        case .shaanxiFemale: return 1.01  // 4.76 → 4.81
        }
    }
}
