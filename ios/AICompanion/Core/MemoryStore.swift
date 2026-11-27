import Foundation

/// 按角色分片持久化：Documents/Memory/<characterID>.json。
/// 用文件而不是 UserDefaults：条目会越攒越多，UserDefaults 整份读写会拖慢启动。
/// 内部加锁，允许后台线程读写（抽取/检索不占主线程）。
final class MemoryStore: @unchecked Sendable {
    static let shared = MemoryStore()

    private let lock = NSLock()
    private var cache: [String: [MemoryEntry]] = [:]
    private let maxPerCharacter = 200
    private let base: URL
    private var didMigrate = false

    /// 按账号分子目录：换号登录不会读到上一个人的记忆
    private var directory: URL {
        let scoped = base.appendingPathComponent(AccountScope.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: scoped, withIntermediateDirectories: true)
        return scoped
    }

    private func cacheKey(_ characterID: String) -> String {
        "\(AccountScope.id)/\(characterID)"
    }

    /// 老版本把记忆直接放在 Memory/ 下：第一次访问时搬进当前账号目录
    private func migrateLegacyIfNeeded() {
        guard !didMigrate else { return }
        didMigrate = true
        let files = (try? FileManager.default.contentsOfDirectory(at: base,
                                                                  includingPropertiesForKeys: nil)) ?? []
        let legacy = files.filter { $0.pathExtension == "json" }
        guard !legacy.isEmpty else { return }
        for file in legacy {
            let dest = directory.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.moveItem(at: file, to: dest)
        }
    }

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        base = documents.appendingPathComponent("Memory", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func entries(for characterID: String) -> [MemoryEntry] {
        lock.lock(); defer { lock.unlock() }
        migrateLegacyIfNeeded()
        let key = cacheKey(characterID)
        if let cached = cache[key] { return cached }
        let stored = loadLocked(characterID)
        let list = decayed(stored)
        if list != stored { saveLocked(characterID, list) }
        cache[key] = list
        return list
    }

    /// 写入：内容相同、或命中词重合 ≥2 的，合并成一条（避免「用户养了猫」出现十遍）
    @discardableResult
    func upsert(_ entry: MemoryEntry) -> MemoryEntry {
        lock.lock(); defer { lock.unlock() }
        var list = cache[cacheKey(entry.characterID)] ?? loadLocked(entry.characterID)

        if let index = list.firstIndex(where: {
            $0.content == entry.content || overlap($0.keys, entry.keys) >= 2
        }) {
            var existing = list[index]
            existing.keys = Array(Set(existing.keys + entry.keys)).sorted()
            if entry.content.count > existing.content.count {
                existing.content = entry.content
            }
            existing.weight = min(3, existing.weight + 0.3)
            existing.lastUsedAt = entry.lastUsedAt ?? existing.lastUsedAt
            list[index] = existing
            cache[cacheKey(entry.characterID)] = list
            saveLocked(entry.characterID, list)
            return existing
        }

        list.append(entry)
        if list.count > maxPerCharacter {
            // 先丢权重最低的，权重相同丢最旧的
            list.sort { lhs, rhs in
                lhs.weight == rhs.weight ? lhs.createdAt > rhs.createdAt : lhs.weight > rhs.weight
            }
            list = Array(list.prefix(maxPerCharacter))
        }
        cache[cacheKey(entry.characterID)] = list
        saveLocked(entry.characterID, list)
        return entry
    }

    func markUsed(ids: [String], characterID: String) {
        guard !ids.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var list = cache[cacheKey(characterID)] ?? loadLocked(characterID)
        let now = Date()
        for index in list.indices where ids.contains(list[index].id) {
            list[index].lastUsedAt = now
        }
        cache[cacheKey(characterID)] = list
        saveLocked(characterID, list)
    }

    func remove(id: String, characterID: String) {
        lock.lock(); defer { lock.unlock() }
        var list = cache[cacheKey(characterID)] ?? loadLocked(characterID)
        list.removeAll { $0.id == id }
        cache[cacheKey(characterID)] = list
        saveLocked(characterID, list)
    }

    /// 有记忆文件的角色 id（给「它记得你什么」列表用）
    func characterIDs() -> [String] {
        lock.lock(); defer { lock.unlock() }
        migrateLegacyIfNeeded()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { !$0.isEmpty }
    }

    func clear(characterID: String) {
        lock.lock(); defer { lock.unlock() }
        cache[cacheKey(characterID)] = []
        saveLocked(characterID, [])
    }

    // MARK: 内部

    /// 权重衰减：30 天没用过的条目慢慢降权，检索时自然往后排。
    /// 只降权不删除——用户的事实不该因为一段时间没提就被丢掉。
    private func decayed(_ list: [MemoryEntry]) -> [MemoryEntry] {
        let now = Date()
        return list.map { entry in
            var item = entry
            let last = item.lastUsedAt ?? item.createdAt
            if now.timeIntervalSince(last) > 30 * 86400, item.weight > 0.5 {
                item.weight = max(0.5, item.weight * 0.9)
            }
            return item
        }
    }

    private func overlap(_ lhs: [String], _ rhs: [String]) -> Int {
        let a = Set(lhs), b = Set(rhs)
        return a.intersection(b).count
    }

    private func fileURL(_ characterID: String) -> URL {
        let safe = characterID.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    private func loadLocked(_ characterID: String) -> [MemoryEntry] {
        guard let data = try? Data(contentsOf: fileURL(characterID)),
              let list = try? JSONDecoder().decode([MemoryEntry].self, from: data) else { return [] }
        return list
    }

    private func saveLocked(_ characterID: String, _ list: [MemoryEntry]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL(characterID), options: .atomic)
    }
}
