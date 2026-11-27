import SwiftUI

struct MineView: View {
    @Environment(AppStore.self) private var store
    @State private var cloud = CloudSession.shared
    @State private var avatarStore = AvatarStore.shared
    @Environment(AppRouter.self) private var router

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// 顶部安全区（灵动岛机型 59pt）——头图要铺到状态栏底下，内容还要躲开它
    private var safeTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 50
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                profileMeta
                    .padding(.horizontal, 18)
                    .padding(.top, 42)
                    .contentShape(Rectangle())
                    .onTapGesture { openProfile() }
                statsRow
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                highlightSection
                    .padding(.horizontal, 18)
                    .padding(.top, 26)
            }
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Palette.bg)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - 头图

    private var hero: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                Image("mine_hero")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: 330)
                    .clipped()
                    .brightness(0.055)
                    .saturation(1.06)
            }
            .frame(height: 330)
            .allowsHitTesting(false)

            // 底部渐隐到页面底色，头像和文字才压得住
            LinearGradient(
                stops: [
                    .init(color: Palette.bg.opacity(0.34), location: 0),
                    .init(color: Palette.bg.opacity(0.0), location: 0.30),
                    .init(color: Palette.bg.opacity(0.35), location: 0.70),
                    .init(color: Palette.bg, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 330)
            .allowsHitTesting(false)

            // 顶部操作区
            VStack {
                HStack(spacing: 0) {
                    Spacer()
                    CircleIconButton(systemName: "bubble.left", tint: .white, badge: store.totalUnread) {
                        router.push(.msgs)
                    }
                    CircleIconButton(systemName: "gearshape", tint: .white) {
                        router.push(.settings)
                    }
                }
                .padding(.trailing, 8)
                .padding(.top, safeTop + 2)
                Spacer()
            }

            // 头像 + 昵称
            HStack(alignment: .center, spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 5) {
                    Text(cloud.isLoggedIn ? cloud.displayName : "点击登录")
                        .font(Typo.body(22, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
                        .lineLimit(1)
                    Text(cloud.isLoggedIn ? "已登录" : "登录后发布自己的角色")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 2)
            .offset(y: 32)
            .contentShape(Rectangle())
            .onTapGesture {
                openProfile()
            }
        }
        .frame(height: 330)
    }

    private var avatar: some View {
        ZStack {
            Group {
                if let image = avatarStore.image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image("mine_avatar").resizable().aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())
        }
        .overlay(
            Circle()
                .stroke(Color(hex: 0x0A0A12), lineWidth: 3)
        )
        .overlay(
            Circle()
                .stroke(Palette.goldGradient, lineWidth: 1.2)
                .padding(-1)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }

    // MARK: - 资料

    private var profileMeta: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标签行
            HStack(spacing: 8) {
                metaChip(icon: "person.fill", text: store.profile.gender)
                metaChip(icon: "mappin.and.ellipse", text: store.profile.city)
                metaChip(text: "LV 0")
                metaChip(text: "未实名")
                Spacer(minLength: 0)
            }

            if !store.profile.signature.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.gold.opacity(0.65))
                        .padding(.top, 2)
                    Text(store.profile.signature)
                        .font(Typo.body(12.5))
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(2)
                }
            }
        }
    }

    /// 点头像/昵称/签名都进「账号资料」；没登录先弹登录
    private func openProfile() {
        if cloud.isLoggedIn {
            router.push(.profile)
        } else {
            AuthGate.shared.needsLogin = true
        }
    }

    private func metaChip(icon: String? = nil, text: String) -> some View {
        HStack(spacing: 3.5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            Text(text)
                .font(Typo.body(10.5))
        }
        .foregroundStyle(.white.opacity(0.62))
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 0.5))
    }

    // MARK: - 数据

    private var totalViews: Int {
        store.myAgents.reduce(0) { $0 + $1.views }
    }

    private var statsRow: some View {
        // 只展示真实存在的数据：没有关注/粉丝功能，就不该摆两个 0 在那里
        HStack(spacing: 0) {
            statItem("\(store.myAgents.count)", "角色")
            divider
            statItem("\(totalViews)", "被浏览")
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.card.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(width: 1, height: 22)
    }

    private func statItem(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
            Text(label)
                .font(Typo.body(10.5))
                .foregroundStyle(Palette.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 高光时刻

    private var highlightSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("高光时刻")
                    .font(Typo.display(19))
                    .tracking(1.5)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if !store.myAgents.isEmpty {
                    Button {
                        router.push(.agents)
                    } label: {
                        HStack(spacing: 2) {
                            Text("全部")
                                .font(Typo.body(12))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Palette.gold)
                        .padding(.leading, 8)
                        .frame(minHeight: Spacing.hit)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看全部角色")
                }
            }
            Text("你创建的角色都在这里")
                .font(Typo.body(12))
                .foregroundStyle(Palette.ink3)
                .padding(.bottom, 14)

            if store.myAgents.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Palette.gold.opacity(0.6))
                    Text("还没有创建过角色")
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.ink3)
                    Button {
                        withAnimation(Motion.quick) { router.tab = .create }
                    } label: {
                        Text("去创建")
                            .font(Typo.body(12.5, weight: .medium))
                            .foregroundStyle(Palette.gold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .overlay(Capsule().stroke(Palette.gold.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(store.myAgents.prefix(4))) { agent in
                        AgentCardView(agent: agent) {
                            let character = store.chatCharacter(for: agent)
                            guard AuthGate.shared.require() else { return }
                                    router.push(.chat(character.id))
                        }
                    }
                }
            }
        }
    }
}
