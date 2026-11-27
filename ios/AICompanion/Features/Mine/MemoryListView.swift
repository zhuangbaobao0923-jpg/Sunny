import SwiftUI

/// A：它记得你什么。逐条可见、可删、可清空——记忆是隐私，用户必须能看见和抹掉。
struct MemoryListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var sections: [MemoryGroup] = []
    @State private var confirmClear = false
    @State private var clearing = false

    struct MemoryGroup: Identifiable {
        let id: String        // characterID
        let name: String
        var entries: [MemoryEntry]
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "它记得你什么", onBack: { dismiss() })

            if sections.isEmpty {
                emptyState
            } else {
                List {
                    ForEach($sections) { $section in
                        Section {
                            ForEach(section.entries) { entry in
                                row(entry)
                                    .listRowBackground(Palette.card)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            MemoryStore.shared.remove(id: entry.id,
                                                                      characterID: section.id)
                                            reload()
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                            }
                        } header: {
                            Text(section.name)
                                .font(Typo.body(11))
                                .foregroundStyle(Palette.ink3)
                        } footer: {
                            if section.id == sections.last?.id {
                                Text("记忆只存在这台手机上，不会上传。你随时可以删掉任意一条。")
                                    .font(Typo.body(10.5))
                                    .foregroundStyle(Palette.ink3)
                                    .padding(.top, 6)
                            }
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            HStack {
                                Spacer()
                                Text(clearing ? "正在清空…" : "清空全部记忆")
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
        .onAppear(perform: reload)
        .alert("清空全部记忆？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clearing = true
                for section in sections {
                    MemoryStore.shared.clear(characterID: section.id)
                }
                clearing = false
                reload()
            }
        } message: {
            Text("所有角色对你的记忆都会被删掉，无法恢复。")
        }
    }

    // MARK: 行

    private func row(_ entry: MemoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.content)
                .font(Typo.body(13.5))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 6) {
                Text(entry.source == .model ? "模型提炼" : "原文摘录")
                Text("·")
                Text(ageText(entry.createdAt))
                if entry.weight > 1.2 {
                    Text("·")
                    Text("重要")
                        .foregroundStyle(Palette.gold)
                }
            }
            .font(Typo.body(10))
            .foregroundStyle(Palette.ink3)
        }
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "brain")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.ink3)
            Text("它现在还不记得关于你的事")
                .font(Typo.body(14, weight: .semibold))
                .foregroundStyle(Palette.ink2)
            Text("多聊几句，说到自己的事\n（比如养了什么、在哪工作、怕什么），它就会记住")
                .font(Typo.body(11.5))
                .foregroundStyle(Palette.ink3)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }

    // MARK: 数据

    private func reload() {
        let ids = MemoryStore.shared.characterIDs()
        sections = ids.compactMap { id in
            let entries = MemoryStore.shared.entries(for: id)
                .sorted { $0.createdAt > $1.createdAt }
            guard !entries.isEmpty else { return nil }
            return MemoryGroup(id: id, name: name(for: id), entries: entries)
        }
        .sorted { $0.name < $1.name }
    }

    private func name(for id: String) -> String {
        if let character = store.character(id: id) { return character.name }
        if id.hasPrefix("agent-") { return String(id.dropFirst("agent-".count)) }
        if let cloud = store.cloudCharacters.first(where: { $0.id == id }) { return cloud.name }
        return "某个角色"
    }

    private func ageText(_ date: Date) -> String {
        let hours = Date().timeIntervalSince(date) / 3600
        if hours < 1 { return "刚刚记住" }
        if hours < 24 { return "\(Int(hours)) 小时前" }
        return "\(Int(hours / 24)) 天前"
    }
}
