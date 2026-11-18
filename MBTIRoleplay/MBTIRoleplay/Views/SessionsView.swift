import SwiftUI

struct SessionsView: View {
    @Environment(AppStore.self) private var store

    private var sortedCharacters: [RoleCharacter] {
        store.characters.sorted { lhs, rhs in
            let l = store.lastMessage(for: lhs.id)?.time ?? .distantPast
            let r = store.lastMessage(for: rhs.id)?.time ?? .distantPast
            return l > r
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(sortedCharacters.enumerated()), id: \.element.id) { index, role in
                    NavigationLink(value: role) {
                        SessionRow(
                            role: role,
                            preview: store.lastMessage(for: role.id),
                            isTyping: store.typing.contains(role.id)
                        )
                    }
                    .buttonStyle(.plain)

                    if index < sortedCharacters.count - 1 {
                        Divider()
                            .overlay(Theme.line)
                            .padding(.leading, 76)
                    }
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.line, lineWidth: 0.8)
            )
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Theme.bg)
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: RoleCharacter.self) { role in
            ChatView(character: role)
        }
    }
}

struct SessionRow: View {
    let role: RoleCharacter
    let preview: ChatMessage?
    let isTyping: Bool

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(character: role, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(role.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    PersonaChip(persona: role.persona, compact: true)
                    Spacer()
                    if let time = preview?.time {
                        Text(relativeTime(time))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.ink3)
                    }
                }

                HStack(spacing: 6) {
                    if isTyping {
                        Text("正在输入…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.accent)
                    } else if let preview {
                        Text(preview.isUser ? "你：\(preview.text)" : preview.text)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink3)
                            .lineLimit(1)
                    } else {
                        Text("还没有开始对话")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink3.opacity(0.8))
                    }
                    Spacer()
                    if role.unread > 0 {
                        UnreadBadge(count: role.unread)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        return date.formatted(.dateTime.month().day())
    }
}
