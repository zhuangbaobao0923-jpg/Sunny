import Foundation

/// 世界书存储：和记忆一样按「账号 / 角色」分片，换号不会读到别人的设定。
/// 与记忆的区别：世界书是**作者写的公共设定**，不随对话变化。
final class LoreStore: @unchecked Sendable {
    static let shared = LoreStore()

    private let lock = NSLock()
    private var cache: [String: [LoreEntry]] = [:]
    private let maxPerCharacter = 100
    private let base: URL

    private var directory: URL {
        let scoped = base.appendingPathComponent(AccountScope.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: scoped, withIntermediateDirectories: true)
        return scoped
    }

    private func cacheKey(_ characterID: String) -> String {
        "\(AccountScope.id)/\(characterID)"
    }

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        base = documents.appendingPathComponent("Lore", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    /// 参与注入的条目（只含启用的）
    func entries(for characterID: String) -> [LoreEntry] {
        allEntries(for: characterID).filter(\.enabled)
    }

    /// 编辑器用：包含被停用的条目
    func allEntries(for characterID: String) -> [LoreEntry] {
        lock.lock(); defer { lock.unlock() }
        let key = cacheKey(characterID)
        if let cached = cache[key] { return cached }
        let list = loadLocked(characterID)
        cache[key] = list
        return list
    }

    @discardableResult
    func upsert(_ entry: LoreEntry) -> LoreEntry {
        lock.lock(); defer { lock.unlock() }
        var list = cache[cacheKey(entry.characterID)] ?? loadLocked(entry.characterID)
        if let index = list.firstIndex(where: { $0.id == entry.id }) {
            list[index] = entry
        } else {
            list.append(entry)
        }
        if list.count > maxPerCharacter {
            list.sort { $0.createdAt > $1.createdAt }
            list = Array(list.prefix(maxPerCharacter))
        }
        cache[cacheKey(entry.characterID)] = list
        saveLocked(entry.characterID, list)
        return entry
    }

    func remove(id: String, characterID: String) {
        lock.lock(); defer { lock.unlock() }
        var list = cache[cacheKey(characterID)] ?? loadLocked(characterID)
        list.removeAll { $0.id == id }
        cache[cacheKey(characterID)] = list
        saveLocked(characterID, list)
    }

    func clear(characterID: String) {
        lock.lock(); defer { lock.unlock() }
        cache[cacheKey(characterID)] = []
        saveLocked(characterID, [])
    }

    func characterIDs() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { !$0.isEmpty }
    }

    // MARK: 内部

    private func fileURL(_ characterID: String) -> URL {
        let safe = characterID.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    private func loadLocked(_ characterID: String) -> [LoreEntry] {
        guard let data = try? Data(contentsOf: fileURL(characterID)),
              let list = try? JSONDecoder().decode([LoreEntry].self, from: data) else { return [] }
        return list
    }

    private func saveLocked(_ characterID: String, _ list: [LoreEntry]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL(characterID), options: .atomic)
    }
}
