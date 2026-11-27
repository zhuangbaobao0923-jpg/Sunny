import SwiftUI

/// 世界书列表：按角色进入编辑。内置角色、自己创建的角色、云端角色都在这里。
struct LoreCharactersView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "世界书", onBack: { dismiss() })

            List {
                Section {
                    ForEach(items) { item in
                        NavigationLink {
                            LoreEditorView(characterID: item.id)
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(item.name.prefix(1)))
                                    .font(Typo.body(14, weight: .semibold))
                                    .foregroundStyle(Palette.gold)
                                    .frame(width: 34, height: 34)
                                    .background(Palette.card2, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(Typo.body(14, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                    Text(item.count == 0 ? "还没有设定" : "\(item.count) 条设定")
                                        .font(Typo.body(10.5))
                                        .foregroundStyle(Palette.ink3)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Palette.card)
                    }
                } footer: {
                    Text("设定只在提到相关关键词时生效，不会一直占着上下文。\n目前世界书存在本机，云端角色发布时暂不同步。")
                        .font(Typo.body(10.5))
                        .foregroundStyle(Palette.ink3)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
        }
        .background(Palette.canvas)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private struct Item: Identifiable {
        let id: String
        let name: String
        let count: Int
    }

    private var items: [Item] {
        var seen = Set<String>()
        var result: [Item] = []

        func append(id: String, name: String) {
            guard !seen.contains(id) else { return }
            seen.insert(id)
            result.append(Item(id: id, name: name,
                               count: LoreStore.shared.allEntries(for: id).count))
        }

        // 已有的 + 还没物化的自定义/云端角色都列出来
        for character in store.characters { append(id: character.id, name: character.name) }
        for agent in store.myAgents {
            append(id: "agent-\(agent.name.trimmingCharacters(in: .whitespaces))", name: agent.name)
        }
        for cloud in store.cloudCharacters { append(id: cloud.id, name: cloud.name) }

        return result.sorted { $0.name < $1.name }
    }
}

/// 某个角色的世界书条目编辑
struct LoreEditorView: View {
    let characterID: String

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var name: String {
        if let character = store.character(id: characterID) { return character.name }
        if characterID.hasPrefix("agent-") { return String(characterID.dropFirst("agent-".count)) }
        if let cloud = store.cloudCharacters.first(where: { $0.id == characterID }) { return cloud.name }
        return "角色"
    }
    @State private var entries: [LoreEntry] = []
    @State private var editing: LoreEntry?
    @State private var confirmClear = false
    @State private var backfilling = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: name, onBack: { dismiss() }) {
                Button {
                    editing = LoreEntry(characterID: characterID, title: "", keys: [], content: "")
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.gold)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新增设定")
            }

            if !weakEntries.isEmpty {
                weakBanner
            }

            if entries.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(entries) { entry in
                            row(entry)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = entry }
                                .listRowBackground(Palette.card)
                            .swipeActions(edge: .leading) {
                                Button {
                                    var updated = entry
                                    updated.enabled.toggle()
                                    LoreStore.shared.upsert(updated)
                                    reload()
                                } label: {
                                    Label(entry.enabled ? "停用" : "启用",
                                          systemImage: entry.enabled ? "eye.slash" : "eye")
                                }
                                .tint(Palette.ink3)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    LoreStore.shared.remove(id: entry.id, characterID: characterID)
                                    reload()
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("左滑停用/启用，右滑删除。停用的条目不参与注入。")
                            .font(Typo.body(10.5))
                            .foregroundStyle(Palette.ink3)
                    }

                    Section {
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("清空这个世界书")
                                    .font(Typo.body(13, weight: .semibold))
                                Spacer()
                            }
                        }
                        .listRowBackground(Palette.card)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Palette.canvas)
            }
        }
        .background(Palette.canvas)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            reload()
            if CommandLine.arguments.contains("-LoreAdd"), entries.isEmpty {
                editing = LoreEntry(characterID: characterID, title: "", keys: [], content: "")
            }
        }
        .sheet(item: $editing) { entry in
            LoreEditSheet(entry: entry, characterID: characterID,
                          characterName: name, bio: characterBio) { saved in
                LoreStore.shared.upsert(saved)
                reload()
            }
        }
        .alert("清空全部设定？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                LoreStore.shared.clear(characterID: characterID)
                reload()
            }
        } message: {
            Text("这个角色的世界书会被清空，无法恢复。")
        }
    }

    /// 关键词少于 2 个的条目：基本不会命中，等于白填
    private var weakEntries: [LoreEntry] {
        entries.filter { $0.enabled && $0.keys.count < 2 }
    }

    private var weakBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Palette.gold)
            Text("有 \(weakEntries.count) 条设定的关键词偏少，可能不会生效")
                .font(Typo.body(11.5))
                .foregroundStyle(Palette.ink2)
            Spacer(minLength: 8)
            Button {
                Task { await backfill() }
            } label: {
                Text(backfilling ? "补全中…" : "一键补全")
                    .font(Typo.body(11, weight: .semibold))
                    .foregroundStyle(backfilling ? Palette.ink3 : Palette.gold)
            }
            .buttonStyle(.plain)
            .disabled(backfilling)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func backfill() async {
        backfilling = true
        defer { backfilling = false }
        for entry in weakEntries {
            let generated = await LoreKeywordExpander.expand(title: entry.title, content: entry.content)
            guard !generated.isEmpty else { continue }
            var updated = entry
            var keys = entry.keys
            for key in generated where !keys.contains(key) { keys.append(key) }
            updated.keys = Array(keys.prefix(10))
            LoreStore.shared.upsert(updated)
        }
        reload()
    }

    private func row(_ entry: LoreEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(entry.title.isEmpty ? "未命名设定" : entry.title)
                    .font(Typo.body(13.5, weight: .medium))
                    .foregroundStyle(entry.enabled ? Palette.ink : Palette.ink3)
                Spacer()
                if entry.priority > 0 {
                    Text(entry.priority == 2 ? "核心" : "重要")
                        .font(Typo.body(9.5, weight: .semibold))
                        .foregroundStyle(entry.priority == 2 ? Palette.gold : Palette.ink2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.card2, in: Capsule())
                }
                if !entry.enabled {
                    Text("已停用")
                        .font(Typo.body(9.5))
                        .foregroundStyle(Palette.ink3)
                }
            }
            Text(entry.content)
                .font(Typo.body(12))
                .foregroundStyle(entry.enabled ? Palette.ink2 : Palette.ink3)
                .lineLimit(2)
            Text(entry.keys.map { "「\($0)」" }.joined())
                .font(Typo.body(10))
                .foregroundStyle(Palette.gold.opacity(0.75))
        }
        .padding(.vertical, 5)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.ink3)
            Text("还没有任何设定")
                .font(Typo.body(14, weight: .semibold))
                .foregroundStyle(Palette.ink2)
            Text("点右上角 + 添加一条\n比如关键词「昆仑」→ 师门在昆仑山")
                .font(Typo.body(11.5))
                .foregroundStyle(Palette.ink3)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }

    /// 角色原人设：用于保存时检测冲突
    private var characterBio: String {
        if let character = store.character(id: characterID) { return character.bio }
        if characterID.hasPrefix("agent-") {
            let name = String(characterID.dropFirst("agent-".count))
            return store.myAgents.first(where: { $0.name == name })?.setting ?? ""
        }
        if let cloud = store.cloudCharacters.first(where: { $0.id == characterID }) { return cloud.bio }
        return ""
    }

    private func reload() {
        entries = LoreStore.shared.allEntries(for: characterID)
            .sorted { ($0.priority, $0.createdAt) > ($1.priority, $1.createdAt) }
    }
}

private struct PriorityOption {
    let value: Int
    let title: String
    static let all = [PriorityOption(value: 0, title: "普通"),
                      PriorityOption(value: 1, title: "重要"),
                      PriorityOption(value: 2, title: "核心")]
}

/// 新增 / 编辑一条设定
struct LoreEditSheet: View {
    let entry: LoreEntry
    let characterID: String
    let characterName: String
    let bio: String
    var onSave: (LoreEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var keysText: String
    @State private var content: String
    @State private var priority: Int
    @State private var error = ""
    @State private var expanding = false
    @State private var conflictNote: String?
    @State private var pendingEntry: LoreEntry?

    init(entry: LoreEntry, characterID: String, characterName: String,
         bio: String, onSave: @escaping (LoreEntry) -> Void) {
        self.entry = entry
        self.characterID = characterID
        self.characterName = characterName
        self.bio = bio
        self.onSave = onSave
        _title = State(initialValue: entry.title)
        _keysText = State(initialValue: entry.keys.joined(separator: "，"))
        _content = State(initialValue: entry.content)
        _priority = State(initialValue: entry.priority)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("给这条设定起个名字", text: $title)
                }
                Section {
                    TextField("点右上角「自动补全」，或自己填", text: $keysText)
                } header: {
                    HStack {
                        Text("关键词")
                        Spacer()
                        Button {
                            Task { await expandIntoField() }
                        } label: {
                            Text(expanding ? "生成中…" : "自动补全")
                                .font(Typo.body(11, weight: .semibold))
                                .foregroundStyle(expanding ? Palette.ink3 : Palette.gold)
                        }
                        .buttonStyle(.plain)
                        .disabled(expanding || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } footer: {
                    Text("用户说到这些词时设定才会生效。\n不用自己想：填好上面的内容，点「自动补全」，系统会把用户可能用的说法都列出来。")
                }
                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 90)
                } header: {
                    Text("设定内容")
                } footer: {
                    Text("一句话说清，用第三人称：\n「她喜欢画画」✅　「你喜欢画画」❌（后者会被理解成用户）")
                }
                Section {
                    HStack(spacing: 8) {
                        ForEach(PriorityOption.all, id: \.value) { option in
                            Button {
                                priority = option.value
                            } label: {
                                Text(option.title)
                                    .font(Typo.body(13, weight: priority == option.value ? .semibold : .regular))
                                    .foregroundStyle(priority == option.value
                                                     ? Color(hex: 0x101018) : Palette.ink2)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        priority == option.value ? Palette.gold : Palette.card2,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("优先级")
                } footer: {
                    Text("核心：每轮都会带上，不用命中关键词（最多 2 条）\n重要：命中时优先占名额\n普通：命中才注入\n每轮最多注入 3 条。")
                        .font(Typo.body(10))
                }
                if !error.isEmpty {
                    Section {
                        Text(error)
                            .font(Typo.body(11))
                            .foregroundStyle(Palette.danger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle(entry.title.isEmpty ? "新增设定" : "编辑设定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Palette.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .font(Typo.body(14, weight: .semibold))
                        .foregroundStyle(Palette.gold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("和原人设冲突", isPresented: Binding(
            get: { conflictNote != nil },
            set: { if !$0 { conflictNote = nil; pendingEntry = nil } }
        )) {
            Button("返回修改", role: .cancel) {
                conflictNote = nil
                pendingEntry = nil
            }
            Button("仍然保存") {
                if let entry = pendingEntry { onSave(entry) }
                conflictNote = nil
                pendingEntry = nil
                dismiss()
            }
        } message: {
            Text("\(conflictNote ?? "")\n\n保存后以新设定为准，角色会按这个说法解释自己的过去，不会生硬否认。")
        }
    }

    /// 手动补全：把结果直接填进输入框，用户能看到、能改
    private func expandIntoField() async {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        expanding = true
        let keys = await LoreKeywordExpander.expand(title: title, content: text)
        expanding = false
        guard !keys.isEmpty else { return }
        let existing = parseKeys()
        var merged = existing
        for key in keys where !merged.contains(key) { merged.append(key) }
        keysText = merged.joined(separator: "，")
    }

    /// 把内容里的第二人称改写成角色名，消除「你指谁」的歧义
    static func thirdPerson(_ text: String, name: String) -> String {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return text }
        var result = text
        for pronoun in ["你们", "您", "你"] {
            if result.hasPrefix(pronoun) {
                result = clean + String(result.dropFirst(pronoun.count))
                break
            }
        }
        return result
    }

    private func parseKeys() -> [String] {
        keysText
            .components(separatedBy: CharacterSet(charactersIn: "，,、 "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        Task { await performSave() }
    }

    @MainActor
    private func performSave() async {
        let keys = keysText
            .components(separatedBy: CharacterSet(charactersIn: "，,、 "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 没填关键词就拿标题兜底：标题通常就是用户会提到的词
        var finalKeys = keys
        if finalKeys.isEmpty {
            let fallback = title.trimmingCharacters(in: .whitespaces)
            if !fallback.isEmpty { finalKeys = [fallback] }
        }
        guard !finalKeys.isEmpty else {
            error = "至少填一个关键词（或填个标题），否则这条设定永远不会生效"
            return
        }
        guard !text.isEmpty else {
            error = "设定内容不能为空"
            return
        }
        guard text.count <= 80 else {
            error = "内容太长（\(text.count) 字），压到 80 字以内"
            return
        }

        var updated = entry
        updated.characterID = characterID
        updated.title = title.trimmingCharacters(in: .whitespaces)
        updated.keys = Array(finalKeys.prefix(6))
        updated.content = text
        updated.priority = priority
        // 和原人设矛盾时，先告诉用户「这条会覆盖原来的说法」，而不是默默保存
        if let note = await LoreConflictChecker.check(content: updated.content, bio: bio) {
            conflictNote = note
            pendingEntry = updated
            return
        }

        onSave(updated)
        dismiss()
    }
}
