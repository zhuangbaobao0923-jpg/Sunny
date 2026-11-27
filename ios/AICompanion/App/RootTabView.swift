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

            // 最小化的通话：悬浮小窗，可上下拖、拖到哪边就贴哪边（位置会记住）
            if call.isMinimized, let callModel = call.model {
                MiniCallBarHost(model: callModel)
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
            Self.startDemoCallIfNeeded(store: store)
        }
    }

    /// 演示/自测辅助：`-DemoCall sjh` 启动即拨通指定角色；
    /// 配合 `-CallSpeed 12` 可以在几十秒内看完「招呼 → 轻问 → 安慰 → 笑话 → 结束语」
    @MainActor
    private static func startDemoCallIfNeeded(store: AppStore) {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-DemoCall") else { return }
        let id = index + 1 < args.count ? args[index + 1] : "sjh"
        guard let character = store.character(id: id) else { return }
        let chatModel = store.makeChatModel(for: character)
        CallCenter.shared.start(chatModel: chatModel, userName: store.profile.nickname)
    }

    /// 演示/截图辅助：`simctl launch ... -StartRoute chat` 直达指定页面，不影响正常启动
    private static func applyLaunchRoute(_ router: AppRouter) {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-StartRoute"),
              index + 1 < args.count else { return }
        switch args[index + 1] {
        case "msgs": router.recPath = [.msgs]
        case "chat": router.recPath = [.chat("sjh")]
        case "chatSwt": router.recPath = [.chat("swt")]
        case "chatNlz": router.recPath = [.chat("nlz")]
        case "create": router.tab = .create
        case "mine": router.tab = .mine
        case "agents": router.tab = .mine; router.minePath = [.agents]
        case "settings": router.tab = .mine; router.minePath = [.settings]
        case "profile": router.tab = .mine; router.minePath = [.settings, .profile]
        case "memory": router.tab = .mine; router.minePath = [.settings, .memory]
        case "lore": router.tab = .mine; router.minePath = [.settings, .lore]
        case "loreEdit": router.tab = .mine; router.minePath = [.settings, .lore, .loreCharacter("sjh")]
        case "loreWeak": router.tab = .mine; router.minePath = [.settings, .lore, .loreCharacter("swt")]
        case "loreAdd": router.tab = .mine; router.minePath = [.settings, .lore, .loreCharacter("agent-萧玄策")]
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
        case .memory:
            MemoryListView()
        case .lore:
            LoreCharactersView()
        case .loreCharacter(let id):
            LoreEditorView(characterID: id)
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

    private static let barHeight: CGFloat = 64      // 胶囊条高度
    private static let fabSize: CGFloat = 54        // 中央圆钮直径
    private static let fabBlock: CGFloat = 72       // 圆钮 + 下方文字的整块高度
    private static let fabGap: CGFloat = 30         // 圆钮探出胶囊的高度（含留白）

    var body: some View {
        // 「AI 创作」点不动的根因：以前圆钮靠 .offset(y: -22) 做视觉上移，
        // 但 offset 只挪绘制、不扩布局——超出父级 64pt 高度的那半圈根本没有命中区域。
        // 现在把整条 TabBar 撑高：胶囊贴底、圆钮贴顶，全部落在 bounds 里，
        // 再给圆钮一块 96×72 的矩形点击面，怎么点都中。
        ZStack(alignment: .top) {
            capsuleBar
                .frame(height: Self.barHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)

            centerButton
                .frame(width: 96, height: Self.fabBlock)
        }
        .frame(height: Self.barHeight + Self.fabGap)
        .padding(.horizontal, 26)
        .padding(.bottom, 6)
    }

    /// 左右两个 tab + 中间给圆钮留位
    private var capsuleBar: some View {
        HStack(spacing: 0) {
            tabButton(.rec, icon: "sparkles", iconFilled: "sparkles", label: "推荐")
            Color.clear
                .frame(width: Self.fabSize + 22)
                .allowsHitTesting(false)
            tabButton(.mine, icon: "person", iconFilled: "person.fill", label: "我的")
        }
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    private func tabButton(_ tab: AppTab, icon: String, iconFilled: String, label: String) -> some View {
        let isOn = selection == tab
        return Button {
            if tab == .create, !AuthGate.shared.require() { return }
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
            guard AuthGate.shared.require() else { return }
            withAnimation(Motion.quick) { selection = .create }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Palette.fabGradient)
                        .frame(width: Self.fabSize, height: Self.fabSize)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("AI 创作")
    }
}

// MARK: - 最小化通话条（可拖动）

/// 悬浮通话条：上下可拖，左右拖过一截就贴到那一侧，位置记在 AppStorage 里。
/// 以前固定在右上角，正好压住收藏和搜索按钮。
private struct MiniCallBarHost: View {
    let model: VoiceCallModel

    @AppStorage("callbar.side") private var sideRaw = "right"
    @AppStorage("callbar.y") private var yFraction = 0.06
    @State private var dragging = false
    @State private var translation: CGSize = .zero

    private let topPadding: CGFloat = 60
    private let bottomReserve: CGFloat = 130

    var body: some View {
        GeometryReader { proxy in
            let usable = max(1, proxy.size.height - topPadding - bottomReserve)
            let baseY = CGFloat(min(1, max(0, yFraction))) * usable

            CallMiniBar(model: model)
                .offset(x: translation.width,
                        y: baseY + (dragging ? translation.height : 0))
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            dragging = true
                            translation = value.translation
                        }
                        .onEnded { value in
                            dragging = false
                            let newY = baseY + value.translation.height
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                yFraction = Double(min(1, max(0, newY / usable)))
                                if value.translation.width < -30 { sideRaw = "left" }
                                if value.translation.width > 30 { sideRaw = "right" }
                                translation = .zero
                            }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: sideRaw == "left" ? .topLeading : .topTrailing)
                .padding(.horizontal, 14)
                .padding(.top, topPadding)
        }
    }
}
