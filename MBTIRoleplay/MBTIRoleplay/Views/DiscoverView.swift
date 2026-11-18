import SwiftUI

struct DiscoverView: View {
    @Environment(AppStore.self) private var store
    @State private var showCreator = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                heroCard
                recommendSection
                sameTypeSection
                creatorCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.bg)
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: RoleCharacter.self) { role in
            ChatView(character: role)
        }
        .sheet(isPresented: $showCreator) {
            CharacterCreatorView()
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("你的人格")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Menu {
                    ForEach(MBTIType.allCases) { type in
                        Button {
                            store.myType = type
                        } label: {
                            Text("\(type.code) · \(type.nickname)")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("切换")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.18)))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.myType.code)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(store.myType.nickname)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text(store.myType.oneLiner)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
            }

            HStack(spacing: 6) {
                ForEach(store.myType.dimensions, id: \.self) { dimension in
                    Text(dimension)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.16)))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var recommendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "为你推荐", subtitle: "按认知功能互补挑选，和你刚好错开的那些人")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.complementaryRoles) { role in
                        NavigationLink(value: role) {
                            RoleCard(role: role)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var sameTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "同好专属", subtitle: "和你人格相近的角色，说话方式你最熟")

            VStack(spacing: 0) {
                ForEach(Array(store.sameTypeRoles.enumerated()), id: \.element.id) { index, role in
                    NavigationLink(value: role) {
                        RoleRow(role: role)
                    }
                    .buttonStyle(.plain)

                    if index < store.sameTypeRoles.count - 1 {
                        Divider().overlay(Theme.line).padding(.leading, 66)
                    }
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.line, lineWidth: 0.8)
            )
        }
    }

    private var creatorCard: some View {
        Button {
            showCreator = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.accentSoft)
                        .frame(width: 46, height: 46)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("捏一个新角色")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("选一个人格类型，行为模式自动补全")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.line, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

struct RoleCard: View {
    let role: RoleCharacter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                AvatarView(character: role, size: 46)
                Spacer()
                PersonaChip(persona: role.persona, compact: true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(role.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(role.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink3)
            }

            Text(role.tagline)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink2)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 32, alignment: .top)

            HStack(spacing: 6) {
                IntimacyDots(level: role.intimacy)
                Text(role.intimacyLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(14)
        .frame(width: 166, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 0.8)
        )
    }
}

struct RoleRow: View {
    let role: RoleCharacter

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(character: role, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(role.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    PersonaChip(persona: role.persona, compact: true)
                }
                Text(role.tagline)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink3.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
