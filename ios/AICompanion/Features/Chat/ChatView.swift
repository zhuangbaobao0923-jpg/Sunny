import SwiftUI

struct ChatView: View {
    let character: Character

    @Environment(AppStore.self) private var store
    @State private var model: ChatModel?

    var body: some View {
        Group {
            if let model {
                ChatScreen(model: model)
            } else {
                ZStack {
                    Palette.canvas
                    ProgressView().tint(Palette.gold)
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model == nil {
                model = store.makeChatModel(for: character)
            }
            // 自测辅助：`-SeedLore` 给当前角色写一条世界设定，用于验证「提到才注入」
            if CommandLine.arguments.contains("-SeedLorePaint") {
                LoreStore.shared.upsert(LoreEntry(
                    characterID: character.id,
                    title: "画画",
                    keys: ["画画", "绘画", "画", "水墨"],
                    content: "纳兰铮喜欢画画，画的是水墨山水，这是她少有的真心爱好。",
                    priority: 2
                ))
            }
            if CommandLine.arguments.contains("-SeedLoreStrong") {
                LoreStore.shared.upsert(LoreEntry(
                    characterID: character.id,
                    title: "心理咨询师",
                    keys: ["心理咨询", "心理咨询师", "工作", "职业"],
                    content: "她现在是执业心理咨询师，这是她真正在做的事。",
                    priority: 2
                ))
            }
            if CommandLine.arguments.contains("-SeedLore") {
                LoreStore.shared.upsert(LoreEntry(
                    characterID: character.id,
                    title: "师门",
                    keys: ["昆仑", "师门"],
                    content: "师门在昆仑山，门规不许弟子下山惹事。",
                    priority: 2
                ))
            }
            // 演示辅助：`simctl launch ... -DemoSend` 自动发送一条消息，验证流式输出
            if let index = CommandLine.arguments.firstIndex(of: "-DemoSend"),
               index + 1 < CommandLine.arguments.count {
                try? await Task.sleep(for: .milliseconds(700))
                model?.input = CommandLine.arguments[index + 1]
                model?.send()
            }
        }
        .onDisappear {
            // 退出页面立即断流，避免后台挂着的 SSE 连接
            model?.cancel()
        }
    }
}

private struct ChatScreen: View {
    @Bindable var model: ChatModel
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var voice = VoiceService.shared

    @State private var showPrompts = false
    /// 默认静音：回复不自动朗读（云端合成按字符计费），点播放键才发声；用户选择持久化
    @AppStorage("chat.muted") private var isMuted = true
    /// 兜底重建输入框用：极少数情况下 TextField 内部文本没跟绑定同步，重建一次必然清空
    /// 输入框清空/聚焦信号：直接作用在 UIKit 控件上，避免重建控件导致键盘抖动
    @State private var showTrace = false
    @State private var showLore = false
    @State private var clearSignal = 0
    @State private var focusSignal = 0

    private var character: Character { model.character }
    private var isSpeakingNow: Bool { voice.speakingID == character.id }

    var body: some View {
        ZStack {
            artwork
            shade

            VStack(spacing: 0) {
                navBar
                intimacyRow
                messageList
                authorRow
                inputBar
            }
            .padding(.bottom, 4)

            if model.showLevelUp {
                LevelUpOverlay(level: model.intimacy.level)
                    .transition(.opacity)
                    .zIndex(8)
            }
        }
        .sheet(isPresented: $showLore) {
            LoreEditorView(characterID: character.id)
        }
        .sheet(isPresented: $showTrace) {
            PromptTraceView()
                .presentationDetents([.medium, .large])
                .presentationBackground(Color(hex: 0x12121C))
        }
        .sheet(isPresented: $showPrompts) {
            PromptSheet(
                character: character,
                aiMessage: model.messages.last(where: { $0.role == .assistant })?.text ?? ""
            ) { suggestion in
                model.input += suggestion
                showPrompts = false
                focusSignal += 1
            }
            .presentationDetents([.height(400)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(hex: 0x12121C))
        }
        .onDisappear {
            store.touchConversation(id: character.id, lastMessage: model.messages.last?.text ?? "")
            // 通话中不打断角色语音：通话自己有朗读与回声处理
            if !CallCenter.shared.isActive { voice.stop() }
        }
        .onAppear {
            // 演示辅助：`-DemoPrompts` 自动弹出引导词面板
            guard CommandLine.arguments.contains("-DemoPrompts") else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(1100))
                showPrompts = true
            }
        }
        // 一条回复流式输出完毕 → 自动用角色音色朗读（语音通话页内部自行朗读，这里让位）
        .onChange(of: model.isStreaming) { _, finished in
            guard finished, !isMuted, !CallCenter.shared.isActive, !Task.isCancelled else { return }
            if let last = model.messages.last, last.role == .assistant, !last.failed, !last.text.isEmpty {
                voice.speak(last.text, for: character, allowBreeze: false)
            }
        }
        .onChange(of: isMuted) { _, muted in
            if muted {
                voice.stop()
            } else if let last = model.messages.last, last.role == .assistant, !last.failed, !last.text.isEmpty {
                // 打开声音的那一刻立刻能听到：直接播最新一条回复
                voice.speak(last.text, for: character, allowBreeze: false)
            }
        }
        // 合成/播放失败不再静默：把原因弹出来，方便真机上定位
        .onChange(of: voice.lastError) { _, error in
            guard let error, !error.isEmpty else { return }
            store.showToast("语音播放失败：\(error)")
        }
    }

    // MARK: - 背景

    private var artwork: some View {
        GeometryReader { geo in
            AgentImage(name: character.imageName, hue: character.hue, saturation: character.saturation)
                .frame(width: geo.size.width, height: geo.size.height)
                .livingGlow(intensity: 0.04)
                .clipped()
        }
        .ignoresSafeArea()
    }

    private var shade: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.bg.opacity(0.8), location: 0),
                .init(color: Palette.bg.opacity(0.25), location: 0.2),
                .init(color: Palette.bg.opacity(0.0), location: 0.38),
                .init(color: Palette.bg.opacity(0.72), location: 0.74),
                .init(color: Palette.bg.opacity(0.98), location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - 顶部

    private var navBar: some View {
        HStack(spacing: 0) {
            CircleIconButton(systemName: "chevron.left") { dismiss() }
            Text(character.name)
                .font(Typo.body(17, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                // 长按标题看这一轮到底注入了什么（自测用，不影响用户）
                .onLongPressGesture(minimumDuration: 0.8) {
                    showTrace = true
                }
            CircleIconButton(systemName: isMuted ? "speaker.slash" : (isSpeakingNow ? "speaker.wave.3" : "speaker.wave.2")) {
                isMuted.toggle()
                store.showToast(isMuted ? "已静音角色语音" : "已开启角色语音")
            }
            Menu {
                Button {
                    showLore = true
                } label: {
                    Label("新增设定", systemImage: "book.closed")
                }
                Button {
                    store.showToast("分享卡片即将上线")
                } label: {
                    Label("分享卡片", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.35), in: Circle())
            }
            .accessibilityLabel("更多")
        }
        .padding(.horizontal, 4)
    }

    private var intimacyRow: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.pink)
                    Text("Lv.\(model.intimacy.level)")
                        .font(Typo.body(13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(model.intimacy.counterText)
                        .font(Typo.body(10.5))
                        .foregroundStyle(Palette.ink2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(hex: 0x12121C).opacity(0.72))
                        .background(.ultraThinMaterial, in: Capsule())
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.pink, Color(hex: 0xFFC3DC)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: 118 * model.intimacy.progress)
                }
                .frame(width: 118, height: 4)
                .animation(Motion.smooth, value: model.intimacy.progress)
            }
        }
        .padding(.trailing, 14)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("亲密度 等级 \(model.intimacy.level)，本轮 \(model.intimacy.roundsIntoLevel) 回合")
    }

    // MARK: - 消息

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.messages) { message in
                        bubble(message)
                            .id(message.id)
                    }
                    if model.isWaitingFirstToken {
                        typingBubble
                            .id("typing")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // 进入聊天页直接定位到底部（最新消息），不用再往下滑
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.count) { scrollToBottom(proxy) }
            .onChange(of: model.messages.last?.text) { scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy, animated: false) }
            // 兜底：LazyVStack 首帧还没排完版时 onAppear 的滚动会落空，稍等再滚一次
            .task {
                try? await Task.sleep(for: .milliseconds(120))
                scrollToBottom(proxy, animated: false)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target: String? = model.isWaitingFirstToken
            ? "typing"
            : model.messages.last.map { "\($0.id)" }
        guard let target else { return }
        if animated {
            withAnimation(Motion.quick) { proxy.scrollTo(target, anchor: .bottom) }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
            if message.failed {
                Button {
                    model.retry()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text(message.text)
                    }
                    .font(Typo.body(13))
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: 0x2A1418).opacity(0.9))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Palette.danger.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                Text(message.text)
                    .font(Typo.body(15))
                    .lineSpacing(5)
                    .foregroundStyle(message.role == .user ? .white : Color(hex: 0x1A1A24))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .background(bubbleBackground(message.role))
                    .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)

                if message.role == .assistant, !message.streaming {
                    voicePlayButton(message)
                }
            }

            Text(TimeLabel.clock(message.date))
                .font(Typo.body(10))
                .foregroundStyle(Palette.ink3)
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "我说：\(message.text)" : "\(character.name)说：\(message.text)")
    }

    /// 气泡下方的语音播放按钮：点哪条播哪条，再点一次停止；不受顶部静音开关影响
    private func voicePlayButton(_ message: ChatMessage) -> some View {
        let isPlayingThis = voice.speakingText == message.text
        // 合成中（云端请求 1~3s）：同一条立即给「合成中」反馈，让人知道没点空
        let isPreparingThis = voice.isPreparing && voice.speakingText == message.text
        return Button {
            if isPlayingThis {
                voice.stop()
            } else {
                voice.speak(message.text, for: character)
            }
        } label: {
            HStack(spacing: 4) {
                if isPreparingThis {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Palette.pink)
                } else {
                    Image(systemName: isPlayingThis ? "stop.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(isPreparingThis ? "合成中…" : (isPlayingThis ? "停止" : "语音播放"))
                    .font(Typo.body(11))
            }
            .foregroundStyle(isPlayingThis || isPreparingThis ? Palette.pink : Palette.ink2)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(hex: 0x12121C).opacity(0.55))
                    .background(.ultraThinMaterial, in: Capsule())
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlayingThis ? "停止播放" : "播放这条语音")
    }

    private func bubbleBackground(_ role: ChatMessage.Role) -> some View {
        let corners = role == .user
            ? RectangleCornerRadii(topLeading: 16, bottomLeading: 16, bottomTrailing: 16, topTrailing: 5)
            : RectangleCornerRadii(topLeading: 5, bottomLeading: 16, bottomTrailing: 16, topTrailing: 16)
        return UnevenRoundedRectangle(cornerRadii: corners, style: .continuous)
            .fill(role == .user ? AnyShapeStyle(Palette.indigo) : AnyShapeStyle(Color(hex: 0xFAFAFC).opacity(0.94)))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }

    private var typingBubble: some View {
        HStack {
            TypingDots()
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(
                    UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(topLeading: 5, bottomLeading: 16, bottomTrailing: 16, topTrailing: 16),
                        style: .continuous
                    )
                    .fill(Color(hex: 0xFAFAFC).opacity(0.94))
                )
            Spacer(minLength: 0)
        }
    }

    // MARK: - 作者行

    private var authorRow: some View {
        HStack(spacing: 9) {
            AgentImage(name: character.imageName, hue: character.hue, saturation: character.saturation)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 1) {
                Text(character.name)
                    .font(Typo.body(14.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                Text(character.author)
                    .font(Typo.body(11))
                    .foregroundStyle(Palette.ink2)
            }

            Spacer()

            Button {
                withAnimation(Motion.quick) { model.toggleLike() }
            } label: {
                HStack(spacing: 6) {
                    Text("\(model.likeCount)")
                        .font(Typo.body(13))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(model.liked ? Palette.pink : .white)
                        .scaleEffect(model.liked ? 1.15 : 1)
                        .shadow(color: model.liked ? Palette.pink.opacity(0.8) : .clear, radius: 6)
                }
                .frame(minWidth: Spacing.hit, minHeight: Spacing.hit, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.liked ? "取消喜欢" : "喜欢该角色")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - 输入

    /// 发送并确保输入框真的清空。
    ///
    /// 坑：`model.send()` 里已经把 input 置空，但 SwiftUI 的 TextField 在
    /// onSubmit（键盘「发送」）提交后，会拿 UITextField 里的旧文本再回写一次绑定，
    /// 把刚清空的值覆盖回去——真机表现就是「消息发出去了，输入框还留着刚才那句话」。
    /// 所以这里在提交后再清两次；万一还是残留，直接重建输入框（必然为空）。
    private func sendInput() {
        let sent = model.input
        guard !sent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.send()
        guard model.input.isEmpty else { return }      // 未发出（比如正在生成）
        clearSentText(sent)
    }

    private func clearSentText(_ sent: String) {
        // 直接从 UIKit 层把文字置空，不重建控件——重建会让键盘重新布局，看起来就是抖一下
        model.input = ""
        clearSignal += 1
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                guard AuthGate.shared.require() else { return }
                CallCenter.shared.start(chatModel: model, userName: store.profile.nickname)
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.pink)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("语音通话")

            ChatInputField(text: $model.input,
                           placeholder: "自由输入...",
                           clearSignal: clearSignal,
                           focusSignal: focusSignal,
                           onSend: sendInput)
                .frame(height: 40)

            Button {
                showPrompts = true
            } label: {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x37D6A0), Color(hex: 0x1FB57F)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("提示词")

            Button {
                if model.isStreaming {
                    model.cancel()
                } else {
                    sendInput()
                }
            } label: {
                Image(systemName: model.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(model.canSend || model.isStreaming ? Color(hex: 0x101018) : Palette.ink3)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(
                            model.canSend || model.isStreaming
                            ? AnyShapeStyle(Palette.fabGradient)
                            : AnyShapeStyle(Color.white.opacity(0.08))
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!model.canSend && !model.isStreaming)
            .accessibilityLabel(model.isStreaming ? "停止生成" : "发送")
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(hex: 0x1C1C28).opacity(0.88))
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

// MARK: - 提示词面板（动态对话引导词）

private struct PromptSheet: View {
    let character: Character
    /// AI 角色的最新发言——引导词必须绑定它实时生成，严禁静态套话
    let aiMessage: String
    let onPick: (String) -> Void

    @State private var suggestions: [QuickReplyEngine.Suggestion] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("✦ 提示词")
                    .font(Typo.body(16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("按\(character.name)最新发言实时生成，可先编辑")
                    .font(Typo.body(11.5))
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
                Spacer()
                Button {
                    withAnimation(Motion.quick) {
                        suggestions = QuickReplyEngine.suggestions(for: character, aiMessage: aiMessage)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink3)
                        .padding(6)
                        .background(Circle().fill(Palette.card))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            onPick(suggestion.text)
                        } label: {
                            HStack(spacing: 10) {
                                Text(suggestion.text)
                                    .font(Typo.body(14))
                                    .foregroundStyle(Palette.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Text(suggestion.tendency.rawValue)
                                    .font(Typo.body(10.5))
                                    .foregroundStyle(Palette.ink3)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().stroke(Palette.line, lineWidth: 1))
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Palette.ink3)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(Palette.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .stroke(Palette.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .onAppear {
            // 每次打开都基于 AI 最新发言实时生成，不用缓存
            suggestions = QuickReplyEngine.suggestions(for: character, aiMessage: aiMessage)
        }
    }
}

// MARK: - 升级特效

private struct LevelUpOverlay: View {
    let level: Int
    @State private var rise = false

    private struct Bubble: Identifiable {
        let id: Int
        let x: CGFloat
        let size: CGFloat
        let delay: Double
    }

    private var bubbles: [Bubble] {
        (0..<18).map { i in
            let seed = Double((i * 41) % 100) / 100
            let seed2 = Double((i * 67) % 100) / 100
            return Bubble(
                id: i,
                x: CGFloat(seed) * 360 - 180,
                size: 8 + CGFloat(seed2) * 18,
                delay: seed2 * 0.6
            )
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.bg.opacity(0.2), Palette.bg.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ForEach(bubbles) { bubble in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: 0xFFD6E8).opacity(0.95),
                                Palette.pink.opacity(0.75),
                                Palette.pinkDeep.opacity(0.25)
                            ],
                            center: UnitPoint(x: 0.32, y: 0.3),
                            startRadius: 0, endRadius: bubble.size
                        )
                    )
                    .frame(width: bubble.size, height: bubble.size)
                    .offset(x: bubble.x, y: rise ? -420 : 320)
                    .opacity(rise ? 0 : 0.9)
                    .animation(
                        .easeOut(duration: 1.8).delay(bubble.delay),
                        value: rise
                    )
            }

            VStack(spacing: 6) {
                Text("Lv.\(level)")
                    .font(Typo.display(64))
                    .foregroundStyle(.white)
                    .shadow(color: Palette.pink.opacity(0.9), radius: 18)
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
                Text("亲密度升级")
                    .font(Typo.body(15))
                    .tracking(6)
                    .foregroundStyle(Palette.pink)
            }
            .scaleEffect(rise ? 1 : 0.6)
            .opacity(rise ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: rise)
        }
        .allowsHitTesting(false)
        .onAppear { rise = true }
    }
}


// MARK: - 输入框（UIKit 支持，清空时不重建控件）

private struct ChatInputField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var clearSignal: Int
    var focusSignal: Int
    var onSend: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.font = UIFont.systemFont(ofSize: 15)
        field.textColor = UIColor(Palette.ink)
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(Palette.ink3)]
        )
        field.returnKeyType = .send
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)),
                        for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.lastClear != clearSignal {
            context.coordinator.lastClear = clearSignal
            field.text = ""
            text = ""
        } else if field.text != text {
            field.text = text
        }

        if context.coordinator.lastFocus != focusSignal {
            context.coordinator.lastFocus = focusSignal
            field.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ChatInputField
        var lastClear: Int
        var lastFocus: Int

        init(_ parent: ChatInputField) {
            self.parent = parent
            lastClear = parent.clearSignal
            lastFocus = parent.focusSignal
        }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSend()
            return false
        }
    }
}


// MARK: - 注入凭证（长按标题查看）

private struct PromptTraceView: View {
    @Environment(\.dismiss) private var dismiss

    private var trace: (time: String, lore: [String], memory: [String]) {
        PromptTrace.snapshot
    }

    var body: some View {
        NavigationStack {
            List {
                Section("时间锚") {
                    Text(trace.time.isEmpty ? "（还没有发送过消息）" : trace.time)
                        .font(Typo.body(12))
                        .foregroundStyle(Palette.ink2)
                }

                Section {
                    if trace.lore.isEmpty {
                        Text("这一轮没有注入任何设定")
                            .font(Typo.body(12))
                            .foregroundStyle(Palette.ink3)
                    } else {
                        ForEach(trace.lore, id: \.self) { line in
                            Text(line)
                                .font(Typo.body(12))
                                .foregroundStyle(Palette.ink2)
                        }
                    }
                } header: {
                    Text("世界书（\(trace.lore.count) 条）")
                } footer: {
                    Text("只有这句话提到关键词时，对应设定才会出现在这里。")
                        .font(Typo.body(10))
                }

                Section {
                    if trace.memory.isEmpty {
                        Text("这一轮没有命中记忆")
                            .font(Typo.body(12))
                            .foregroundStyle(Palette.ink3)
                    } else {
                        ForEach(trace.memory, id: \.self) { line in
                            Text(line)
                                .font(Typo.body(12))
                                .foregroundStyle(Palette.ink2)
                        }
                    }
                } header: {
                    Text("记忆（\(trace.memory.count) 条）")
                } footer: {
                    Text("这是上一轮请求实际带进模型的内容，不是推测。")
                        .font(Typo.body(10))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle("这一轮注入了什么")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Palette.gold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
