import SwiftUI

struct RecView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @ObservedObject private var voice = VoiceService.shared

    @State private var index = 0
    @State private var isLoading = true
    @State private var expandedBio = false
    @State private var typingText = ""
    @State private var dragOffset: CGFloat = 0
    /// 本次进入时洗好的推荐池（含用户创建的角色）
    @State private var feed: [Character] = []

    private var character: Character {
        if feed.isEmpty { return store.characters.first ?? SampleData.characters[0] }
        return feed[index % feed.count]
    }

    private var isSpeakingNow: Bool { voice.speakingID == character.id }
    private var isPreparingNow: Bool { voice.isPreparing && voice.speakingText == character.opening }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            artwork
            shade

            VStack(spacing: 0) {
                topBar
                Text("——  \(character.name)  ——")
                    .font(Typo.display(19))
                    .tracking(5)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.75), radius: 5, y: 2)
                    .padding(.top, 6)
                    .contentTransition(.opacity)

                Spacer(minLength: 0)

                bottomContent
            }
            .padding(.bottom, 146)

            if isLoading {
                skeleton
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .contentShape(Rectangle())
        .gesture(swipeGesture)
        .task {
            guard isLoading else { return }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.35)) { isLoading = false }
        }
        // 每次进入推荐页都重新洗牌：官方角色 + 用户创建的角色一起推送
        .onAppear {
            feed = store.recommendationFeed()
            index = 0
        }
        .task(id: character.id) {
            voice.stop()
            await typewriter()
        }
        .onDisappear {
            voice.stop()
        }
    }

    // MARK: - 立绘

    private var artwork: some View {
        GeometryReader { geo in
            AgentImage(name: character.imageName, hue: character.hue, saturation: character.saturation)
                .frame(width: geo.size.width, height: geo.size.height)
                .livingGlow()
                .id(character.id)
                .transition(.opacity)
                .clipped()
        }
        .ignoresSafeArea()
    }

    private var shade: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.bg.opacity(0.62), location: 0),
                .init(color: Palette.bg.opacity(0.0), location: 0.26),
                .init(color: Palette.bg.opacity(0.0), location: 0.44),
                .init(color: Palette.bg.opacity(0.78), location: 0.72),
                .init(color: Palette.bg.opacity(0.97), location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - 顶部

    private var topBar: some View {
        HStack(spacing: 0) {
            Text("推荐")
                .font(Typo.body(18, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)

            Spacer(minLength: 8)

            CircleIconButton(systemName: "bubble.left", tint: .white, badge: store.totalUnread) {
                router.push(.msgs)
            }
            CircleIconButton(systemName: "magnifyingglass", tint: .white) {
                store.showToast("搜索功能开发中")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.top, 4)
    }

    // MARK: - 底部内容

    private var bottomContent: some View {
        VStack(spacing: 10) {
            bioCard
            quoteBubble

            Text("上滑切换下一个角色")
                .font(Typo.body(10.5))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 8)

            Button {
                store.markRead(character.id)
                guard AuthGate.shared.require() else { return }
                                    router.push(.chat(character.id))
            } label: {
                Text("开始聊天")
                    .foregroundStyle(.white)
                    .font(Typo.body(16, weight: .semibold))
                    .tracking(6)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        Capsule()
                            .fill(Color(hex: 0x161620).opacity(0.7))
                            .background(.ultraThinMaterial, in: Capsule())
                    )
                    .overlay(Capsule().stroke(Palette.line2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.top, 6)
        }
        .padding(.horizontal, 16)
    }

    private var bioCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.gold)
                    Text("背景介绍 · \(character.author)")
                        .font(Typo.body(13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(character.bio)
                    .font(Typo.body(12.5))
                    .lineSpacing(4)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(expandedBio ? nil : 2)
                    .animation(Motion.quick, value: expandedBio)

                Text(expandedBio ? "收起" : "展开")
                    .font(Typo.body(11.5))
                    .foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Motion.quick) { expandedBio.toggle() }
        }
    }

    private var quoteBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(typingText)
                    .font(Typo.body(13.5))
                    .lineSpacing(4)
                    .foregroundStyle(.white)
                BlinkingCursor()
            }

            Button {
                voice.toggle(character.opening, for: character)
            } label: {
                HStack(spacing: 8) {
                    if isPreparingNow {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Palette.pink)
                    } else {
                        Waveform(color: isSpeakingNow ? Palette.pink : Palette.ink3, animated: isSpeakingNow)
                    }
                    Text(isPreparingNow ? "正在合成声音…" : (isSpeakingNow ? "正在用 TA 的声音和你说话" : "点击播放 TA 的声音"))
                        .font(Typo.body(11.5))
                        .foregroundStyle(isSpeakingNow || isPreparingNow ? Palette.pink : Palette.ink3)
                }
            }
            .buttonStyle(.plain)
            .disabled(typingText != character.opening)
            .opacity(typingText != character.opening ? 0.4 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 5, bottomLeadingRadius: 16,
                bottomTrailingRadius: 16, topTrailingRadius: 16,
                style: .continuous
            )
            .fill(Color(hex: 0xFAFAFC).opacity(0.14))
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 5, bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16, topTrailingRadius: 16,
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .frame(maxWidth: 330, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 骨架屏

    private var skeleton: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            ShimmerBlock(corner: 0, base: Color(hex: 0x15151F), highlight: Color(hex: 0x1E1E2C))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Spacer()
                ShimmerBlock().frame(width: 120, height: 16)
                ShimmerBlock().frame(width: 200, height: 16)
                ShimmerBlock(corner: 16).frame(height: 64)
                ShimmerBlock().frame(height: 48)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
    }

    // MARK: - 交互

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                defer { withAnimation(Motion.quick) { dragOffset = 0 } }
                guard abs(value.translation.height) > 60,
                      abs(value.translation.height) > abs(value.translation.width) else { return }
                advance(by: value.translation.height < 0 ? 1 : -1)
            }
    }

    private func advance(by delta: Int) {
        let count = feed.count
        guard count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            index = (index + delta + count) % count
            expandedBio = false
        }
    }

    private func typewriter() async {
        typingText = ""
        for ch in character.opening {
            if Task.isCancelled { return }
            typingText.append(ch)
            try? await Task.sleep(for: .milliseconds(26))
        }
    }
}

/// 打字机光标
struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Palette.gold)
            .frame(width: 2, height: 14)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
            .padding(.leading, 2)
    }
}
