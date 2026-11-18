import SwiftUI

struct CreateView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var draft = AgentDraft()
    @State private var showVoicePicker = false
    @State private var showFaceStudio = false
    @State private var didAttemptSubmit = false
    @State private var isAutoFilling = false
    /// 上一次「自动生成」实际写进表单的结果。用于判断：
    /// 用户没改任何内容再点一次 → 生成完全不同的新人设；用户改过 → 以用户改动为基础重写
    @State private var lastAutoFill: PersonaAutofill?
    @FocusState private var focusedField: Field?

    /// 截图调试标记：整个进程只自动弹一次形象工作室
    private static var demoFacePresented = false

    private enum Field: Hashable { case nickname, setting, intro, opening }

    var body: some View {
        ZStack {
            Palette.canvas

            // ScrollView + 底部按钮用 VStack 排：按钮永远贴在屏幕底部，
            // 键盘弹出时整块上移，不会再出现「按钮浮在页面中间」的错位
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        faceCard
                        voiceSection
                        personaSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                footer
            }

            if showFaceStudio {
                FaceStudioView(
                    hint: faceContextHint,
                    onPick: { image, hue, saturation in
                        draft.imageName = image
                        draft.hue = hue
                        draft.saturation = saturation
                        withAnimation(Motion.smooth) { showFaceStudio = false }
                    },
                    onClose: { withAnimation(Motion.smooth) { showFaceStudio = false } }
                )
                .zIndex(20)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { focusedField = nil }
                    .foregroundStyle(Palette.gold)
            }
        }
        .onAppear {
            // 调试入口：-DemoFace 直接打开形象生成面板（仅演示/截图用）。
            // 只认一次：以前每次回到本页都会自动弹出形象窗，用户会以为「点返回就弹窗」。
            if ProcessInfo.processInfo.arguments.contains("-DemoFace"), !Self.demoFacePresented {
                Self.demoFacePresented = true
                showFaceStudio = true
            }
        }
        .onDisappear { showFaceStudio = false }
        .sheet(isPresented: $showVoicePicker) {
            VoicePickerSheet(selection: $draft.voice)
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(hex: 0x12121C))
        }
    }

    /// 生图上下文：把已填的昵称/性别/设定摘要喂给文生图，形象贴合人设
    private var faceContextHint: String {
        var parts: [String] = []
        let name = draft.nickname.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { parts.append("角色名字「\(name)」") }
        if let gender = draft.gender, gender != "暂不透露" { parts.append("性别：\(gender)") }
        let setting = draft.setting.trimmingCharacters(in: .whitespaces)
        if !setting.isEmpty { parts.append("人物设定摘要：\(String(setting.prefix(60)))") }
        return parts.joined(separator: "；")
    }

    // MARK: - 顶部

    private var header: some View {
        HStack {
            Button {
                // 返回 = 先退出上层（形象工作室/键盘），再回上一页；
                // 不再出现「点了返回却弹出形象窗」的层级错乱
                if showFaceStudio {
                    withAnimation(Motion.smooth) { showFaceStudio = false }
                    return
                }
                focusedField = nil
                withAnimation(Motion.quick) { router.tab = .rec }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: Spacing.hit, height: Spacing.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Spacer()

            Text("创建智能体")
                .font(Typo.body(18, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Palette.ink)

            Spacer()

            Text("AI 辅助")
                .font(Typo.body(11))
                .foregroundStyle(Palette.gold.opacity(0.85))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(Palette.gold.opacity(0.35), lineWidth: 1))
                .allowsHitTesting(false)
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    // MARK: - 形象

    private var faceCard: some View {
        Button {
            focusedField = nil
            withAnimation(Motion.smooth) { showFaceStudio = true }
        } label: {
            ZStack {
                if let imageName = draft.imageName {
                    // 完整展示人物（模糊底 + 等比全图），不再只露出一张脸
                    ZStack {
                        AgentImage(name: imageName, hue: draft.hue, saturation: draft.saturation)
                            .blur(radius: 24)
                            .opacity(0.5)
                        AgentImage(name: imageName, hue: draft.hue, saturation: draft.saturation,
                                   contentMode: .fit)
                            .padding(.vertical, 8)
                    }
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Text("重新生成")
                            .font(Typo.body(11.5))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Palette.bg.opacity(0.72)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                            .padding(10)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.gold)
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(Palette.gold.opacity(0.6), lineWidth: 1.5))
                        Text("点击设定 Ta 的容颜、形象")
                            .font(Typo.body(12.5))
                            .foregroundStyle(Palette.ink3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        draft.imageName == nil ? Palette.gold.opacity(0.4) : Palette.line2,
                        style: StrokeStyle(lineWidth: draft.imageName == nil ? 1.5 : 1,
                                           dash: draft.imageName == nil ? [6, 5] : [])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(draft.imageName == nil ? "添加智能体形象" : "重新生成智能体形象")
    }

    // MARK: - 声音

    private var voiceSection: some View {
        section(title: "智能体声音") {
            VStack(spacing: 0) {
                settingRow(
                    label: "智能体声音",
                    value: draft.voice ?? "添加音色",
                    required: true,
                    isFilled: draft.voice != nil
                ) {
                    focusedField = nil
                    showVoicePicker = true
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Palette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            if didAttemptSubmit && draft.isVoiceMissing {
                Text("请选择智能体声音")
                    .font(Typo.body(11.5))
                    .foregroundStyle(Palette.danger)
                    .padding(.top, 6)
            }
        }
    }

    private func settingRow(
        label: String,
        value: String,
        required: Bool,
        isFilled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(Typo.body(15))
                    .foregroundStyle(Palette.ink)
                if required {
                    Text("*").font(Typo.body(12)).foregroundStyle(Palette.gold)
                }
                Spacer()
                Text(value)
                    .font(Typo.body(14))
                    .foregroundStyle(isFilled ? Palette.ink : Palette.ink3)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 人设

    private var personaSection: some View {
        section(
            title: "智能体人设",
            action: {
                Button {
                    focusedField = nil
                    autoFill()
                } label: {
                    HStack(spacing: 5) {
                        if isAutoFilling {
                            ProgressView()
                                .tint(Palette.gold)
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "wand.and.stars").font(.system(size: 11))
                        }
                        Text(isAutoFilling ? "生成中…" : "自动生成")
                            .font(Typo.body(12.5, weight: .medium))
                    }
                    .foregroundStyle(isAutoFilling ? Palette.ink3 : Palette.gold)
                    // 放大点击热区，解决「不灵敏」
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isAutoFilling)
                .accessibilityLabel("自动生成人设")
            }
        ) {
            VStack(spacing: 18) {
                field(
                    title: "昵称",
                    required: true,
                    error: didAttemptSubmit && draft.nickname.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "请填写昵称" : nil
                ) {
                    TextField("", text: $draft.nickname,
                              prompt: Text("给你的智能体命名").foregroundStyle(Palette.ink3))
                        .textFieldStyle(.plain)
                        .font(Typo.body(14.5))
                        .foregroundStyle(Palette.ink)
                        .focused($focusedField, equals: .nickname)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .padding(13)
                        .background(inputBackground)
                }

                field(
                    title: "性别（不可二次更改）",
                    required: true,
                    error: didAttemptSubmit && draft.gender == nil ? "请选择性别" : nil
                ) {
                    HStack(spacing: 10) {
                        ForEach(["男", "女", "暂不透露"], id: \.self) { option in
                            let isOn = draft.gender == option
                            Button {
                                draft.gender = option
                            } label: {
                                Text(option)
                                    .font(Typo.body(14, weight: isOn ? .semibold : .regular))
                                    .foregroundStyle(isOn ? Color(hex: 0x2A1F08) : Palette.ink2)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(
                                        Capsule().fill(isOn ? AnyShapeStyle(Palette.goldGradient)
                                                             : AnyShapeStyle(Color.clear))
                                    )
                                    .overlay(
                                        Capsule().stroke(isOn ? Color.clear : Palette.line2, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                field(
                    title: "智能体设定",
                    hint: "（决定回复效果）",
                    required: true,
                    error: didAttemptSubmit && draft.setting.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "请填写智能体设定" : nil
                ) {
                    TextEditor(text: $draft.setting)
                        .focused($focusedField, equals: .setting)
                        .font(Typo.body(14.5))
                        .foregroundStyle(Palette.ink)
                        .scrollContentBackground(.hidden)
                        .frame(height: 108)
                        .padding(9)
                        .background(inputBackground)
                        .overlay(alignment: .topLeading) {
                            if draft.setting.isEmpty {
                                Text("此处填写智能体的语言、思维、身份、背景、经历、聊天风格、与用户（主控）的关系等，其他人无法看到")
                                    .font(Typo.body(14.5))
                                    .foregroundStyle(Palette.ink3)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 17)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                field(
                    title: "对外简介",
                    hint: "（不影响对话效果，仅用于展示）",
                    required: true,
                    error: didAttemptSubmit && draft.intro.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "请填写对外简介" : nil
                ) {
                    TextEditor(text: $draft.intro)
                        .focused($focusedField, equals: .intro)
                        .font(Typo.body(14.5))
                        .foregroundStyle(Palette.ink)
                        .scrollContentBackground(.hidden)
                        .frame(height: 108)
                        .padding(9)
                        .background(inputBackground)
                        .overlay(alignment: .topLeading) {
                            if draft.intro.isEmpty {
                                Text("在此处输入你想说的话，及希望用户了解的智能体信息，如背景、身份、人设、与用户的关系等")
                                    .font(Typo.body(14.5))
                                    .foregroundStyle(Palette.ink3)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 17)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                field(
                    title: "开场白",
                    required: true,
                    error: didAttemptSubmit && draft.opening.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "请填写开场白" : nil
                ) {
                    TextEditor(text: $draft.opening)
                        .focused($focusedField, equals: .opening)
                        .font(Typo.body(14.5))
                        .foregroundStyle(Palette.ink)
                        .scrollContentBackground(.hidden)
                        .frame(height: 86)
                        .padding(9)
                        .background(inputBackground)
                        .overlay(alignment: .topLeading) {
                            if draft.opening.isEmpty {
                                Text("与 Ta 的第一句话，用于开启聊天")
                                    .font(Typo.body(14.5))
                                    .foregroundStyle(Palette.ink3)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 17)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Palette.card)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
            )
    }

    // MARK: - 通用分段容器

    private func section<Content: View>(
        title: String,
        @ViewBuilder action: () -> some View = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.gold)
                Text(title)
                    .font(Typo.body(14.5, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                action()
            }
            content()
        }
        .padding(.top, 22)
    }

    private func field<Content: View>(
        title: String,
        hint: String? = nil,
        required: Bool,
        error: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(title)
                    .font(Typo.body(13.5))
                    .foregroundStyle(Palette.ink)
                if required {
                    Text("*").font(Typo.body(12)).foregroundStyle(Palette.gold)
                }
                if let hint {
                    Text(hint)
                        .font(Typo.body(11.5))
                        .foregroundStyle(Palette.ink3)
                }
            }
            content()
            if let error {
                Text(error)
                    .font(Typo.body(11.5))
                    .foregroundStyle(Palette.danger)
            }
        }
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(spacing: 0) {
            Button {
                focusedField = nil
                submit()
            } label: {
                Text("创建智能体")
            }
            .buttonStyle(GoldButtonStyle(enabled: draft.canSubmit))
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 6)
        }
        .background(
            ZStack {
                Palette.bg.ignoresSafeArea(edges: .bottom)
                LinearGradient(colors: [Palette.bg.opacity(0), Palette.bg],
                               startPoint: .top, endPoint: .bottom)
                    .padding(.top, -24)
            }
        )
    }

    // MARK: - 行为

    private func submit() {
        didAttemptSubmit = true
        guard draft.canSubmit else {
            store.showToast("还差：\(draft.missingFields.joined(separator: "、"))")
            return
        }
        let agent = store.createAgent(from: draft)
        draft = AgentDraft()
        didAttemptSubmit = false
        lastAutoFill = nil
        showFaceStudio = false
        // 创建成功后直接进入这个新智能体的对话页（不再跳回首页推荐）
        let character = store.chatCharacter(for: agent)
        router.tab = .rec
        router.recPath = [.chat(character.id)]
    }

    private func autoFill() {
        guard !isAutoFilling else { return }
        isAutoFilling = true

        let nickname = draft.nickname
        let gender = draft.gender
        let prev = lastAutoFill

        func same(_ a: String, _ b: String) -> Bool {
            a.trimmingCharacters(in: .whitespacesAndNewlines)
                == b.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 上次生成之后，用户有没有亲手改过内容
        let userEdited: Bool = {
            guard let prev else { return false }
            return !same(draft.setting, prev.setting)
                || !same(draft.intro, prev.intro)
                || !same(draft.opening, prev.opening)
        }()
        // 只有「用户自己写的 / 改过的」才作为重写基础。
        // 上次自动生成的原样内容绝不能当成「用户设定必须延续」——那是旧版复读的根源。
        let hasPrev = prev != nil
        let baseSetting = (hasPrev && !userEdited) ? "" : draft.setting
        let baseIntro = (hasPrev && !userEdited) ? "" : draft.intro
        let baseOpening = (hasPrev && !userEdited) ? "" : draft.opening
        let avoid = (hasPrev && !userEdited) ? prev : nil

        store.showToast(userEdited ? "正在按你的修改重写人设…" : "AI 正在换一个人设…")

        Task {
            var out: PersonaAutofill
            do {
                out = try await PersonaAutofillEngine.generate(
                    nickname: nickname,
                    gender: gender,
                    userSetting: baseSetting,
                    userIntro: baseIntro,
                    userOpening: baseOpening,
                    avoidPrevious: avoid,
                    direction: PersonaAutofillEngine.directions.randomElement()
                )
                // 模型偶尔会复读上一次：再要一版；还一样就本地兜底，保证用户看到变化
                if let prev,
                   PersonaAutofillEngine.looksSame(out.setting, prev.setting)
                    || PersonaAutofillEngine.looksSame(out.intro, prev.intro) {
                    if let retry = try? await PersonaAutofillEngine.generate(
                        nickname: nickname,
                        gender: gender,
                        userSetting: baseSetting,
                        userIntro: baseIntro,
                        userOpening: baseOpening,
                        avoidPrevious: avoid ?? prev,
                        direction: PersonaAutofillEngine.directions.randomElement()
                    ) {
                        out = retry
                    }
                    if PersonaAutofillEngine.looksSame(out.setting, prev.setting) {
                        out = PersonaAutofillEngine.localFallback(nickname: nickname, gender: gender)
                    }
                }
            } catch {
                out = PersonaAutofillEngine.localFallback(nickname: nickname, gender: gender)
            }
            withAnimation(.easeOut(duration: 0.3)) {
                applyAutofill(out)
                isAutoFilling = false
            }
            store.showToast(
                out.direction == "本地方案"
                    ? "已生成本地方案（配置模型后效果更佳）"
                    : "已换一版新人设 · \(out.direction)"
            )
        }
    }

    /// 每次点击都覆盖设定/简介/开场白；昵称仅在为空时采用建议值，性别不可二次更改故不动。
    private func applyAutofill(_ out: PersonaAutofill) {
        if draft.nickname.isEmpty, let suggested = out.nickname {
            draft.nickname = suggested
        }
        if draft.gender == nil, let suggested = out.gender,
           ["男", "女"].contains(suggested) {
            draft.gender = suggested
        }
        if !out.setting.isEmpty { draft.setting = out.setting }
        if !out.intro.isEmpty { draft.intro = out.intro }
        if !out.opening.isEmpty { draft.opening = out.opening }
        // 记下「表单里真实的内容」，下次据此判断用户有没有手动改过
        lastAutoFill = PersonaAutofill(
            nickname: out.nickname,
            gender: out.gender,
            setting: draft.setting,
            intro: draft.intro,
            opening: draft.opening,
            direction: out.direction
        )
    }
}

// MARK: - 音色选择

private struct VoicePickerSheet: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var genderFilter: String? = nil
    @State private var previewer = PreviewPlayer()

    private var options: [(name: String, gender: String, desc: String)] {
        SampleData.voiceOptions.filter { genderFilter == nil || $0.gender == genderFilter }
    }

    /// 音色名 → edge-tts 参数（统一取自 VoiceKind 映射，避免两处数据漂移）
    private func ttsParams(for name: String) -> (voice: String, rate: String, pitch: String) {
        let kind = VoiceKind.kind(for: name)
        return (kind.edgeVoice, kind.edgeRate, kind.edgePitch)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置智能体声音")
                .font(Typo.body(17, weight: .semibold))
                .foregroundStyle(Palette.ink)

            HStack(spacing: 8) {
                filterChip("全部", value: nil)
                filterChip("男", value: "男")
                filterChip("女", value: "女")
                filterChip("儿童", value: "儿童")
                Spacer()
            }

            if let error = previewer.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Typo.body(12))
                    .foregroundStyle(Palette.goldDeep)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(options, id: \.name) { option in
                        Button {
                            selection = option.name
                            previewer.stop()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Button {
                                    let p = ttsParams(for: option.name)
                                    let sample = option.gender == "儿童"
                                        ? "你好呀，我是你的小伙伴，我们做朋友吧！"
                                        : "你好，我是你的智能体，这种声音你觉得如何？"
                                    previewer.toggle(
                                        text: sample,
                                        voice: p.voice, rate: p.rate, pitch: p.pitch,
                                        tag: option.name,
                                        kind: VoiceKind.kind(for: option.name)
                                    )
                                } label: {
                                    Image(systemName: previewer.isPlaying && previewer.tag == option.name ? "pause.fill" : "play.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.gold)
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(Palette.gold.opacity(0.12)))
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.name)
                                        .font(Typo.body(14.5, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                    Text(option.desc)
                                        .font(Typo.body(11.5))
                                        .foregroundStyle(Palette.ink3)
                                }
                                Spacer()
                                if selection == option.name {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.gold)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(Palette.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .stroke(selection == option.name ? Palette.goldDeep : Palette.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(18)
        .onDisappear { previewer.stop() }
    }

    private func filterChip(_ title: String, value: String?) -> some View {
        let isOn = genderFilter == value
        return Button {
            genderFilter = value
        } label: {
            Text(title)
                .font(Typo.body(12))
                .foregroundStyle(isOn ? Palette.gold : Palette.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isOn ? Palette.gold.opacity(0.1) : .clear)
                )
                .overlay(Capsule().stroke(isOn ? Palette.goldDeep : Palette.line2, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
