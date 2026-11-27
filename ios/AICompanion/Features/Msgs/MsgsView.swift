import SwiftUI

struct MsgsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var filter: ConversationFilter = .all

    private enum ConversationFilter: String, CaseIterable {
        case all = "全部"
        case unread = "未读"
    }

    private var conversations: [Character] {
        // 没有对话记录的角色不进热聊（自定义角色创建后不该空占一条）
        let base = store.characters
            .filter { !$0.lastMessage.isEmpty || $0.unread > 0 }
            .sorted { $0.lastActivity > $1.lastActivity }
        switch filter {
        case .all: return base
        case .unread: return base.filter { $0.unread > 0 }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "热聊", onBack: { dismiss() }) {
                Menu {
                    ForEach(ConversationFilter.allCases, id: \.self) { item in
                        Button(item.rawValue) { filter = item }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(filter.rawValue)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.ink2)
                    .frame(minWidth: Spacing.hit, minHeight: Spacing.hit, alignment: .trailing)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("我的热聊")
                            .font(Typo.body(16, weight: .bold))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 2)

                    Text("聊过的人物角色都展示在这里")
                        .font(Typo.body(12))
                        .foregroundStyle(Palette.ink3)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)

                    if conversations.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(conversations) { character in
                                Button {
                                    store.markRead(character.id)
                                    guard AuthGate.shared.require() else { return }
                                    router.push(.chat(character.id))
                                } label: {
                                    row(character)
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(Palette.line).padding(.leading, 82)
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.canvas)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ character: Character) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                AgentImage(name: character.imageName, hue: character.hue, saturation: character.saturation)
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                if character.unread > 0 {
                    Circle()
                        .fill(Palette.danger)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Palette.bg, lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(character.name)
                        .font(Typo.body(15.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let tag = character.tags.first {
                        Text(tag)
                            .font(Typo.body(9.5))
                            .foregroundStyle(Palette.gold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Capsule().stroke(Palette.gold.opacity(0.45), lineWidth: 1))
                    }
                }
                Text(character.lastMessage)
                    .font(Typo.body(12.5))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Text(TimeLabel.listLabel(character.lastActivity))
                    .font(Typo.body(11))
                    .foregroundStyle(Palette.ink3)
                if character.unread > 0 {
                    Text("\(character.unread)")
                        .font(Typo.body(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(Palette.danger))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.ink3)
                .padding(.bottom, 6)
            Text("还没有聊过天")
            Text("去「推荐」找一个角色开始对话吧")
        }
        .font(Typo.body(13))
        .foregroundStyle(Palette.ink3)
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}
