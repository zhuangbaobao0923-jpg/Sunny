import AVFoundation

/// 拨号回铃音（Ringback）。
/// 中国标准回铃音：450Hz 正弦波，响 1 秒、停 4 秒，循环。
/// 不用音频文件——直接在内存里生成 5 秒一个周期的 PCM 缓冲区循环播放，
/// 体积为零、无需资源管理，也不会被静音开关以外的东西影响。
final class RingbackTone {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var connected = false     // 是否已 attach + connect
    private(set) var isRinging = false

    private static let sampleRate: Double = 44100
    private static let toneHz: Double = 450
    private static let onSeconds: Double = 1.0
    private static let offSeconds: Double = 4.0

    func start(volume: Float = 0.32) {
        guard !isRinging else { return }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)

        guard let buf = buffer ?? Self.makePattern() else { return }
        buffer = buf

        if !connected {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buf.format)
            connected = true
        }
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return }
        }

        player.volume = volume
        // .loops 让 5 秒周期无缝循环：20 秒正好 4 声「嘟——」
        player.scheduleBuffer(buf, at: nil, options: .loops)
        player.play()
        isRinging = true
    }

    func stop() {
        guard isRinging else { return }
        isRinging = false
        player.stop()
        if engine.isRunning { engine.pause() }
    }

    // MARK: - 波形生成

    private static func makePattern() -> AVAudioPCMBuffer? {
        let sr = sampleRate
        let cycle = onSeconds + offSeconds
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(sr * cycle)) else { return nil }
        buf.frameLength = AVAudioFrameCount(sr * cycle)
        guard let channel = buf.floatChannelData?[0] else { return nil }

        let total = Int(buf.frameLength)
        let onSamples = Int(sr * onSeconds)
        let fade = Int(sr * 0.02)      // 20ms 淡入淡出，消除爆音

        for i in 0..<total {
            guard i < onSamples else {
                channel[i] = 0
                continue
            }
            let t = Double(i) / sr
            var env = 1.0
            if i < fade { env = Double(i) / Double(fade) }
            else if onSamples - i < fade { env = Double(onSamples - i) / Double(fade) }
            channel[i] = Float(sin(2 * Double.pi * toneHz * t) * 0.30 * env)
        }
        return buf
    }
}
