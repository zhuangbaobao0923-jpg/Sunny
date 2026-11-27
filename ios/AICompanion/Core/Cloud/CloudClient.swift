import Foundation
import Observation
import Security

/// 云服务配置（来自 WorkBuddy 云服务 publicConfig，可放在前端）
enum CloudConfig {
    static let endpoint = "https://night-talk-14472.app.workbuddy.host"
    static let publishableKey = "wbpk_vcwLgnVJcbmmjhxbgQ5wPE_fhafle3pjrI2ksB0CKD77JupaeIee7m0"
}

/// 当前生效的账号作用域：本地数据（聊天记录/记忆）按它分目录，
/// 同一台手机换账号不会串数据。未登录 = guest。
enum AccountScope {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current = "guest"

    static var id: String {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    static func set(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        current = value.isEmpty ? "guest" : value
    }
}

enum CloudError: LocalizedError {
    case message(String)
    case network

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .network: return "网络不太顺，稍后再试"
        }
    }
}

// MARK: - 会话

/// 登录态：手机号 + 密码（注册时用一次短信验证码）。
/// token 存 Keychain，重启 App 仍是登录状态。
@MainActor
@Observable
final class CloudSession {
    static let shared = CloudSession()

    private(set) var userId: String = ""
    private(set) var phone: String = ""
    private(set) var isBusy = false
    private(set) var lastError: String = ""

    private var accessToken: String = ""
    private var refreshToken: String = ""
    private var expiresAt = Date.distantPast
    private var profileName: String = ""

    var isLoggedIn: Bool { !accessToken.isEmpty }
    /// 展示用昵称：手机号中间打码
    var displayName: String {
        if !profileName.isEmpty { return profileName }
        guard phone.count == 11 else { return phone.isEmpty ? "夜谈用户" : phone }
        return phone.prefix(3) + "****" + phone.suffix(4)
    }

    private init() {
        restore()
        AccountScope.set(userId)
    }

    // MARK: 注册 / 登录

    /// 云端要求 `+86 138xxxx` 这种格式（中间有空格），
    /// 直接发 11 位会返回 invalid_argument
    static func normalizedPhone(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        var local = digits
        if local.hasPrefix("0086") {
            local = String(local.dropFirst(4))
        } else if local.hasPrefix("86"), local.count == 13 {
            local = String(local.dropFirst(2))
        }
        return local.count == 11 && local.hasPrefix("1") ? "+86 \(local)" : phone
    }

    /// 发短信验证码，返回 verificationId
    func sendCode(phone: String) async throws -> (verificationId: String, existing: Bool) {
        let body: [String: Any] = ["phone_number": Self.normalizedPhone(phone), "target": "ANY"]
        let data = try await post("/.cloud/auth/v1/verification", body: body, authed: false)
        guard let vid = data["verification_id"] as? String else {
            throw CloudError.message("验证码没发出去，稍后再试")
        }
        return (vid, data["is_existing_user"] as? Bool ?? false)
    }

    /// 校验验证码，拿一次性 verificationToken
    func verifyCode(verificationId: String, code: String) async throws -> String {
        let body: [String: Any] = ["verification_id": verificationId, "verification_code": code]
        let data = try await post("/.cloud/auth/v1/verification/verify", body: body, authed: false)
        guard let token = data["verification_token"] as? String else {
            throw CloudError.message("验证码不对，或已经过期")
        }
        return token
    }

    /// 注册（验证码 + 设密码）
    func register(phone: String, verificationToken: String, password: String) async throws {
        let body: [String: Any] = [
            "phone_number": Self.normalizedPhone(phone),
            "password": password,
            "verification_token": verificationToken
        ]
        let data = try await post("/.cloud/auth/v1/signup", body: body, authed: false)
        try applySession(data, phone: phone)
    }

    /// 手机号 + 密码登录
    func signIn(phone: String, password: String) async throws {
        let body: [String: Any] = ["username": Self.normalizedPhone(phone), "password": password]
        let data = try await post("/.cloud/auth/v1/signin", body: body, authed: false)
        try applySession(data, phone: phone)
    }

    func signOut() {
        accessToken = ""
        refreshToken = ""
        userId = ""
        phone = ""
        expiresAt = .distantPast
        AccountScope.set("")
        CloudKeychain.remove("cloud.session")
    }

    // MARK: 内部

    private func applySession(_ data: [String: Any], phone: String) throws {
        guard let token = data["access_token"] as? String, !token.isEmpty else {
            throw CloudError.message("登录失败：服务端没返回会话")
        }
        accessToken = token
        refreshToken = data["refresh_token"] as? String ?? ""
        let ttl = (data["expires_in"] as? Double) ?? 3600
        expiresAt = Date().addingTimeInterval(ttl)
        self.phone = phone
        if let user = data["user"] as? [String: Any] {
            userId = (user["id"] as? String) ?? ""
        }
        AccountScope.set(userId)
        save()
    }

    private func save() {
        let dict: [String: Any] = [
            "access": accessToken,
            "refresh": refreshToken,
            "expires": expiresAt.timeIntervalSince1970,
            "user": userId,
            "phone": phone
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            CloudKeychain.save(data, for: "cloud.session")
        }
    }

    private func restore() {
        guard let data = CloudKeychain.load("cloud.session"),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        accessToken = dict["access"] as? String ?? ""
        refreshToken = dict["refresh"] as? String ?? ""
        expiresAt = Date(timeIntervalSince1970: dict["expires"] as? Double ?? 0)
        userId = dict["user"] as? String ?? ""
        phone = dict["phone"] as? String ?? ""
    }

    /// 拿一个可用 token；过期就续期
    func validToken() async throws -> String {
        if !accessToken.isEmpty, expiresAt > Date().addingTimeInterval(30) {
            return accessToken
        }
        guard !refreshToken.isEmpty else {
            throw CloudError.message("登录已过期，请重新登录")
        }
        let data = try await post("/.cloud/auth/v1/token",
                                  body: ["grant_type": "refresh_token", "refresh_token": refreshToken],
                                  authed: false)
        guard let token = data["access_token"] as? String else {
            throw CloudError.message("登录已过期，请重新登录")
        }
        accessToken = token
        if let newRefresh = data["refresh_token"] as? String { refreshToken = newRefresh }
        let ttl = (data["expires_in"] as? Double) ?? 3600
        expiresAt = Date().addingTimeInterval(ttl)
        save()
        return token
    }

    // MARK: HTTP

    func post(_ path: String, body: [String: Any], authed: Bool) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: CloudConfig.endpoint + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "x-wb-webapp-access-key")
        if authed {
            let token = try await validToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudError.network }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            var msg = (json["message"] as? String)
                ?? (json["error"] as? String)
                ?? (json["msg"] as? String)
                ?? "操作失败（\(http.statusCode)）"
            if msg == "invalid_argument" {
                msg = "手机号格式不对，要 11 位大陆号码"
            }
            throw CloudError.message(msg)
        }
        return json
    }

    /// 数据库请求（PostgREST）：返回原始 JSON
    func database(_ method: String, table: String, query: String = "",
                  body: Any? = nil, prefer: String? = nil) async throws -> Any {
        let url = URL(string: "\(CloudConfig.endpoint)/.cloud/database/rest/\(table)\(query)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(CloudConfig.publishableKey, forHTTPHeaderField: "x-wb-webapp-access-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = try await validToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudError.network }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw CloudError.message("云端返回 \(http.statusCode)：\(text.prefix(120))")
        }
        return (try? JSONSerialization.jsonObject(with: data)) ?? []
    }
}

// MARK: - 云端角色

struct CloudAgent: Identifiable {
    let id: Int64
    let name: String
    let tagline: String
    let persona: String
    let opening: String
    let ownerName: String
    let voiceKind: String?
}

@MainActor
enum CloudAgents {
    /// 已发布的全部角色（首页推荐用）
    static func fetchPublished() async throws -> [CloudAgent] {
        let query = "?select=id,name,tagline,persona,opening,owner_name,voice_kind&published=eq.true&order=created_at.desc&limit=50"
        let raw = try await CloudSession.shared.database("GET", table: "agents", query: query)
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"] as? Int64 ?? (row["id"] as? Int).map(Int64.init),
                  let name = row["name"] as? String else { return nil }
            return CloudAgent(
                id: id,
                name: name,
                tagline: row["tagline"] as? String ?? "",
                persona: row["persona"] as? String ?? "",
                opening: row["opening"] as? String ?? "",
                ownerName: row["owner_name"] as? String ?? "夜谈用户",
                voiceKind: row["voice_kind"] as? String
            )
        }
    }

    /// 删除自己发布的全部角色（RLS 限定只能删自己的行）
    static func deleteMine() async throws {
        _ = try await CloudSession.shared.database("DELETE", table: "agents", query: "?id=gt.0")
    }

    /// 发布一个角色（发布即公开）
    static func publish(name: String, tagline: String, persona: String,
                        opening: String, voice: String?) async throws {
        let body: [String: Any] = [
            "name": name,
            "tagline": tagline,
            "persona": persona,
            "opening": opening,
            "owner_name": CloudSession.shared.displayName,
            "voice_kind": voice ?? "",
            "published": true
        ]
        _ = try await CloudSession.shared.database("POST", table: "agents",
                                                   body: body, prefer: "return=representation")
    }
}

// MARK: - Keychain

enum CloudKeychain {
    static func save(_ data: Data, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 云端角色 → 本地角色

extension Character {
    /// 把云端发布的角色转成可以直接聊天的角色
    static func cloud(_ agent: CloudAgent, index: Int) -> Character {
        let images = ["char_shenjinghan", "char_nalanzheng", "char_xiewujiu", "char_lingyunshang"]
        return Character(
            id: "cloud-\(agent.id)",
            name: agent.name,
            author: agent.ownerName,
            imageName: images[index % images.count],
            hue: Double(agent.id % 5) * 11,
            saturation: 1,
            tags: ["用户创作"],
            bio: agent.tagline.isEmpty ? agent.persona : agent.tagline,
            opening: agent.opening,
            replies: [],
            voiceKind: VoiceKind.kind(for: agent.voiceKind),
            voiceName: agent.voiceKind,
            likeCount: 0,
            liked: false,
            unread: 0,
            lastMessage: "",
            lastActivity: .distantPast
        )
    }
}

// MARK: - 登录闸门

/// 未登录时点任何需要账号的功能：统一弹一次登录页，而不是到处写 if
@MainActor
@Observable
final class AuthGate {
    static let shared = AuthGate()
    var needsLogin = false

    private init() {}

    /// 已登录返回 true；未登录则弹出登录页并返回 false
    @discardableResult
    func require() -> Bool {
        if CloudSession.shared.isLoggedIn { return true }
        needsLogin = true
        return false
    }
}
