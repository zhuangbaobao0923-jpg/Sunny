import SwiftUI

struct RootTabView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var call = CallCenter.shared

    var body: some View {
        @Bindable var router = router

        ZStack(alignment: .bottom) {
            Palette.canvas

            Group {
                switch router.tab {
                case .rec:
                    NavigationStack(path: $router.recPath) {
                        RecView()
                            .navigationDestination(for: Route.self) { route in
                                destination(route)
                            }
                    }
                case .create:
                    NavigationStack {
                        CreateView()
                    }
                case .mine:
                    NavigationStack(path: $router.minePath) {
                        MineView()
                            .navigationDestination(for: Route.self) { route in
                                destination(route)
                            }
                    }
                }
            }
            .transition(.opacity)

            if router.showsTabBar {
                TabBar(selection: $router.tab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let toast = store.toast {
                ToastView(text: toast)
                    .padding(.bottom, 120)
                    .allowsHitTesting(false)
                    .zIndex(10)
            }

            // 最小化的通话：右上角悬浮小窗，通话继续（麦克风与计时不中断）
            if call.isMinimized, let callModel = call.model {
                CallMiniBar(model: callModel)
                    .padding(.trailing, 14)
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .zIndex(30)
            }
        }
        .background(Palette.bg)
        .animation(Motion.quick, value: router.showsTabBar)
        .animation(Motion.smooth, value: call.isMinimized)
        // 通话页：全屏展示 / 上滑收起 = 最小化（不挂断）
        .fullScreenCover(isPresented: Binding(
            get: { call.isFullScreen && call.model != nil },
            set: { presented in
                if !presented { CallCenter.shared.minimize() }
            }
        )) {
            if let callModel = call.model {
                VoiceCallView(model: callModel)
            }
        }
        .task {
            Self.applyLaunchRoute(router)
        }
    }

    /// 演示/截图辅助：`simctl launch ... -StartRoute chat` 直达指定页面，不影响正常启动
    private static func applyLaunchRoute(_ router: AppRouter) {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-StartRoute"),
              index + 1 < args.count else { return }
        switch args[index + 1] {
        case "msgs": router.recPath = [.msgs]
        case "chat": router.recPath = [.chat("sjh")]
        case "create": router.tab = .create
        case "mine": router.tab = .mine
        case "agents": router.tab = .mine; router.minePath = [.agents]
        case "settings": router.tab = .mine; router.minePath = [.settings]
        case "voice": router.tab = .mine; router.minePath = [.settings, .voice]
        case "model": router.tab = .mine; router.minePath = [.settings, .model]
        default: break
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .msgs:
            MsgsView()
        case .agents:
            AgentsView()
        case .chat(let id):
            if let character = store.character(id: id) {
                ChatView(character: character)
            } else {
                Text("角色不存在").foregroundStyle(Palette.ink2)
            }
        case .settings:
            SettingsView()
        case .profile:
            ProfileView()
        case .voice:
            VoiceSettingsView()
        case .model:
            ModelSettingsView()
        }
    }
}

// MARK: - 底部导航（悬浮胶囊条）

private struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.rec, icon: "sparkles", iconFilled: "sparkles", label: "推荐")
            centerButton
            tabButton(.mine, icon: "person", iconFilled: "person.fill", label: "我的")
        }
        .frame(height: 64)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .padding(.horizontal, 26)
        .padding(.bottom, 6)
    }

    private func tabButton(_ tab: AppTab, icon: String, iconFilled: String, label: String) -> some View {
        let isOn = selection == tab
        return Button {
            withAnimation(Motion.quick) { selection = tab }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isOn ? iconFilled : icon)
                    .font(.system(size: 19, weight: isOn ? .semibold : .regular))
                    .frame(height: 24)
                Text(label)
                    .font(Typo.body(10.5, weight: isOn ? .semibold : .regular))
                    .tracking(0.5)
                Capsule()
                    .fill(isOn ? Palette.gold : Palette.gold.opacity(0.0))
                    .frame(width: 14, height: 2.5)
            }
            .foregroundStyle(isOn ? Palette.gold : Palette.ink3)
            .animation(Motion.quick, value: isOn)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var centerButton: some View {
        Button {
            withAnimation(Motion.quick) { selection = .create }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Palette.fabGradient)
                        .frame(width: 54, height: 54)
                        .shadow(color: Palette.gold.opacity(0.35), radius: 12, y: 5)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 8)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x101018))
                }
                Text("AI创作")
                    .font(Typo.body(10.5, weight: selection == .create ? .semibold : .regular))
                    .tracking(0.5)
                    .foregroundStyle(selection == .create ? Palette.gold : Palette.ink3)
            }
            .offset(y: -22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI 创作")
    }
}
