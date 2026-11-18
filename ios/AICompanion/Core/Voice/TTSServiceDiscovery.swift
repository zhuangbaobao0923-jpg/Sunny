import Foundation
import Network

/// 通过 Bonjour 自动发现 Mac 上的本地 TTS 服务（_edgetts._tcp）。
/// 真机无需手输 IP；发现成功后自动写入 VoiceSettings.baseURLString。
/// 首次使用会弹「本地网络」权限弹窗，点允许即可；拒绝或找不到时可在设置页手输 IP。
///
/// 解析策略：用 NetService 解析服务的 sockaddr 列表并取 IPv4
/// （Network.framework 的 NWConnection 解析在双栈 Wi-Fi 下可能选 IPv6 link-local，
/// 而 URL 无法携带 scope 后缀，IPv4 是唯一稳妥选择）；
/// 全部尝试失败后周期重试，服务晚些出现也能被发现。
@MainActor
@Observable
final class TTSServiceDiscovery {
    static let shared = TTSServiceDiscovery()

    /// 最近一次发现的服务地址（如 http://192.168.169.2:9880）
    private(set) var discoveredBaseURL: String?
    /// 发现状态（设置页展示）
    private(set) var state: State = .idle

    enum State: Equatable {
        case idle
        case browsing
        case found(String)
        case notFound
    }

    /// 发现成功后的回调（VoiceService 注册：发现即重测连接状态）
    var onFound: ((String) -> Void)?

    private var browser: NWBrowser?
    private var resolving = false
    private var retryTask: Task<Void, Never>?

    func startBrowsing() {
        // 支持重启：notFound 后再次调用时重建浏览器
        browser?.cancel()
        browser = nil
        retryTask?.cancel()
        resolving = false
        state = .browsing

        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(
            for: .bonjour(type: "_edgetts._tcp.", domain: nil),
            using: params
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.resolving, self.discoveredBaseURL == nil,
                      let endpoint = results.first?.endpoint else { return }
                self.resolving = true
                self.resolve(endpoint: endpoint)
            }
        }
        browser.stateUpdateHandler = { [weak self] newState in
            if case .failed(let error) = newState {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.state = .notFound
                    self.lastError = "发现服务失败：\(error.localizedDescription)"
                    self.scheduleRetry()
                }
            }
        }
        browser.start(queue: .global(qos: .utility))
        self.browser = browser
        // 12 秒内没发现就报「未找到」（browser 保留，服务晚些出现仍会被发现）
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, case .browsing = self.state, self.discoveredBaseURL == nil else { return }
            self.state = .notFound
            self.scheduleRetry()
        }
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        retryTask?.cancel()
    }

    private var lastError: String?

    /// 解析失败后的延时重试
    private func scheduleRetry(delay: Double = 4) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.discoveredBaseURL == nil else { return }
            self.resolving = false
            self.state = .browsing
            // 重新启动一轮浏览 + 解析
            self.startBrowsing()
        }
    }

    /// 把 Bonjour endpoint 解析成 IPv4 地址（NetService 解析 sockaddr，过滤 AF_INET）
    nonisolated private func resolve(endpoint: NWEndpoint) {
        guard case let .service(name, type, domain, _) = endpoint else {
            Task { @MainActor [weak self] in self?.resolveFailed() }
            return
        }
        let resolver = ServiceResolver(
            domain: domain.isEmpty ? "local." : domain,
            type: type.hasSuffix(".") ? type : type + ".",
            name: name
        ) { [weak self] ipv4, port in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let ipv4, let port {
                    self.finishResolve(url: "http://\(ipv4):\(port)")
                } else {
                    self.resolveFailed()
                }
            }
        }
        resolver.start()
    }

    private func resolveFailed() {
        resolving = false
        scheduleRetry()
    }

    private func finishResolve(url: String) {
        Task {
            let client = LocalTTSClient(baseURLString: url)
            do {
                try await client.health()
                discoveredBaseURL = url
                state = .found(url)
                if VoiceSettings.shared.baseURLString != url {
                    VoiceSettings.shared.baseURLString = url
                }
                onFound?(url)
            } catch {
                // 地址拿到了但健康检查失败，稍后重试
                resolving = false
                state = .browsing
                scheduleRetry(delay: 3)
            }
        }
    }
}

// MARK: - NetService 解析器（独立对象持有 delegate，防提前释放）

private final class ServiceResolver: NSObject, NetServiceDelegate {
    private let completion: (_ ipv4: String?, _ port: Int?) -> Void
    private var service: NetService?
    private var done = false

    init(domain: String, type: String, name: String,
         completion: @escaping (_ ipv4: String?, _ port: Int?) -> Void) {
        self.completion = completion
        super.init()
        let service = NetService(domain: domain, type: type, name: name)
        service.delegate = self
        self.service = service
    }

    func start() {
        guard let service else { return }
        // 解析回调依赖 runloop；挂在主 runloop common 模式即可
        service.schedule(in: .main, forMode: .common)
        service.resolve(withTimeout: 6)
        // 兜底超时
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self, !self.done else { return }
            self.done = true
            self.service?.stop()
            self.completion(nil, nil)
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard !done else { return }
        done = true
        let port = sender.port
        var ipv4: String?
        for data in sender.addresses ?? [] {
            let family = data.withUnsafeBytes { $0.load(as: sockaddr.self).sa_family }
            guard family == UInt8(AF_INET) else { continue }
            var addr = data.withUnsafeBytes { $0.load(as: sockaddr_in.self) }
            var ip = in_addr()
            ip.s_addr = addr.sin_addr.s_addr
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &ip, &buf, socklen_t(INET_ADDRSTRLEN))
            let host = String(cString: buf)
            if !host.isEmpty, host != "0.0.0.0" {
                ipv4 = host
                break
            }
        }
        sender.stop()
        completion(ipv4, ipv4 != nil ? port : nil)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        guard !done else { return }
        done = true
        sender.stop()
        completion(nil, nil)
    }
}
