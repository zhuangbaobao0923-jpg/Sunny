import AVFoundation
import Foundation

// MARK: - 流式 PCM 播放
//
// Breeze 的 /stream 返回 24 kHz / 16-bit / 单声道裸 PCM。
// 这里用 AVAudioEngine + AVAudioPlayerNode 边收边排，收到约 0.3 秒就先出声，
// 不再等整段音频生成完。

@MainActor
final class BreezeStreamPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format: AVAudioFormat

    private var pending = Data()
    private var scheduled = 0
    private var completed = 0
    private var scheduledBytes = 0
    private var streamEnded = false
    private var playing = false
    private var stopped = false

    private var onStart: (() -> Void)?
    private var onFinish: (() -> Void)?

    /// 预缓冲 0.3 秒：24000 × 2 字节 × 0.3
    private let prebufferBytes = 14_400

    init?() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        ) else { return nil }
        self.format = format
    }

    func start(onStart: @escaping () -> Void, onFinish: @escaping () -> Void) throws {
        self.onStart = onStart
        self.onFinish = onFinish

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        CallAudioSession.prepareForPlayback()
        try engine.start()
    }

    func append(_ data: Data) {
        guard !stopped else { return }
        pending.append(data)

        let evenCount = pending.count - (pending.count % 2)
        guard evenCount >= 2 else { return }
        let chunk = pending.prefix(evenCount)
        pending = pending.subdata(in: evenCount..<pending.count)
        schedule(Data(chunk))

        if !playing, scheduledBytes >= prebufferBytes {
            node.play()
            playing = true
            onStart?()
        }
    }

    func finish() {
        guard !stopped else { return }
        streamEnded = true
        // 极短音频：还没到预缓冲阈值，直接播
        if !playing {
            node.play()
            playing = true
            onStart?()
        }
        maybeFinish()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        node.stop()
        engine.stop()
    }

    private func schedule(_ data: Data) {
        let frames = data.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frames)
              ) else { return }

        buffer.frameLength = AVAudioFrameCount(frames)
        if let dst = buffer.int16ChannelData?[0] {
            data.copyBytes(
                to: UnsafeMutableRawBufferPointer(start: dst, count: frames * 2)
            )
        }

        scheduled += 1
        scheduledBytes += data.count

        node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.completed += 1
                self.maybeFinish()
            }
        }
    }

    private func maybeFinish() {
        guard streamEnded, completed >= scheduled else { return }
        stop()
        onFinish?()
    }
}

// MARK: - 流式 HTTP 请求

final class BreezeStreamingRequest: NSObject, URLSessionDataDelegate {
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var statusCode = 0
    private var errorBody = Data()
    private var totalBytes = 0
    private var finished = false

    private let onData: (Data) -> Void
    private let onComplete: (Error?) -> Void

    init(
        request: URLRequest,
        onData: @escaping (Data) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        self.onData = onData
        self.onComplete = onComplete
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        task = session.dataTask(with: request)
        task?.resume()
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        task?.cancel()
        session.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if statusCode == 200 {
            totalBytes += data.count
            if totalBytes == data.count {
            }
            onData(data)
        } else if errorBody.count < 600 {
            errorBody.append(data)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        finished = true

        if let error {
            onComplete(error)
        } else if statusCode != 200 {
            let message = String(data: errorBody, encoding: .utf8) ?? "HTTP \(statusCode)"
            onComplete(BreezeTTSClient.TTSError.badResponse(statusCode, message))
        } else {
            onComplete(nil)
        }
        session.finishTasksAndInvalidate()
    }
}
