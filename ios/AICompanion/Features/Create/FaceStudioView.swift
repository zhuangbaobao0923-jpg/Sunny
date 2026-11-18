import SwiftUI

/// 形象工作室（页面内全屏层，不再用 sheet）
///
/// 之前用 `.sheet` + `.presentationDetents` 呈现，返回键/键盘一通操作会让它反复弹出，
/// 而且内容区高度被弹窗压扁：人物图只剩一张脸、键盘顶住「生成图片」。
/// 现在改成页面内独立层：返回键 = 关闭工作室，布局自己说了算。
struct FaceStudioView: View {
    /// 角色上下文（昵称/性别/设定摘要），拼进生图提示词，让形象贴合人设
    var hint: String = ""
    let onPick: (String, Double, Double) -> Void
    let onClose: () -> Void

    @State private var style = "经典"
    @State private var description = ""
    @State private var isGenerating = false
    @State private var isFilling = false
    @State private var stageIndex = 0
    @State private var plans: [VisualPlan] = []
    @State private var selectedID: UUID?
    @State private var batch = 0
    @State private var failureNote: String?
    @State private var generationID = 0
    @FocusState private var descFocused: Bool
    @State private var showFullImage = false

    /// 竖版 3:4，比 768x1344 更快出图，也更适合完整展示人物
    private static let imageSize = "864x1152"   // 3:4，竖版立绘

    private let ideas = [
        "银发红瞳、一袭黑衣的古风剑客",
        "白衬衫、清爽短发的学长",
        "墨发金瞳，执灯而立的皇子",
        "双马尾、抱着课本的元气少女",
        "穿风衣的长发画师，指尖沾着颜料"
    ]
    private let stages = ["解析描述…", "勾勒线稿…", "铺色渲染…", "细化神态…"]

    private var selected: VisualPlan? { plans.first { $0.id == selectedID } }

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: 0x0A0A12).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        styleRow
                        describeField      // 先写描述、再出图：不用滚动就能边改边生成
                        preview
                        if selected != nil { candidates }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) { bottomBar }
            }
        }
        .overlay {
            if showFullImage, let selected {
                ZStack {
                    Color(hex: 0x05050A).ignoresSafeArea()
                    AgentImage(name: imgName(selected), hue: selected.hue, saturation: selected.saturation,
                               contentMode: .fit)
                        .padding(.horizontal, 6)
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { showFullImage = false }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(Color.white.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                            .padding(.top, 8)
                        }
                        Spacer()
                        Text("整张图 · 点任意处返回")
                            .font(Typo.body(11.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.bottom, 24)
                    }
                }
                .transition(.opacity)
                .zIndex(30)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { showFullImage = false }
                }
            }
        }
        // 键盘工具条由外层 CreateView 提供（同一 NavigationStack 下不要挂两套，会出两个「完成」）
        .onAppear { runDemoIfNeeded() }
        .transition(.move(edge: .bottom))
    }

    // MARK: - 顶部

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                    Text("返回")
                        .font(Typo.body(14))
                }
                .foregroundStyle(Palette.ink2)
                .frame(height: Spacing.hit)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭形象工作室")

            Spacer(minLength: 4)

            Text("创建智能体形象")
                .font(Typo.body(15.5, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .layoutPriority(1)

            Spacer(minLength: 4)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink3)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .frame(width: Spacing.hit, height: Spacing.hit)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    // MARK: - 画风

    private var styleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SampleData.artStyles, id: \.self) { item in
                    Button { style = item } label: {
                        Text(item)
                            .font(Typo.body(12.5))
                            .foregroundStyle(style == item ? Palette.gold : Palette.ink2)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(style == item ? Palette.gold.opacity(0.14) : Color.white.opacity(0.05)))
                            .overlay(Capsule().stroke(style == item ? Palette.goldDeep : Palette.line2, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 大图预览（完整人物）

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: 0x14141F))

            if let selected {
                // 背景：同一张图模糊铺满，负责填满卡片
                AgentImage(name: imgName(selected), hue: selected.hue, saturation: selected.saturation)
                    .blur(radius: 26)
                    .opacity(0.38)
                // 主体：固定 3:4（与出图比例一致），fit = 完整人物，绝不裁切。
                // 之前把竖图塞进横向卡片再 fit，两侧全是空白，看起来像被切了。
                AgentImage(name: imgName(selected), hue: selected.hue, saturation: selected.saturation,
                           contentMode: .fit)
                    .frame(width: 246, height: 328)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) { showFullImage = true }
                    }
            } else if isGenerating {
                VStack(spacing: 12) {
                    ProgressView().tint(Palette.gold).scaleEffect(1.15)
                    Text(stages[min(stageIndex, stages.count - 1)])
                        .font(Typo.body(12.5))
                        .foregroundStyle(Palette.ink2)
                    HStack(spacing: 5) {
                        ForEach(stages.indices, id: \.self) { i in
                            Capsule()
                                .fill(i <= stageIndex ? AnyShapeStyle(Palette.goldGradient) : AnyShapeStyle(Palette.line2))
                                .frame(height: 3)
                        }
                    }
                    .padding(.horizontal, 60)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "paintbrush.pointed")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Palette.gold.opacity(0.6))
                        .frame(width: 46, height: 46)
                        .overlay(Circle().stroke(Palette.gold.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    Text("生成的全身形象会显示在这里")
                        .font(Typo.body(13))
                        .foregroundStyle(Palette.ink3)
                    Text("选画风、写一句描述，点下面「生成图片」")
                        .font(Typo.body(11.5))
                        .foregroundStyle(Palette.ink3.opacity(0.75))
                }
            }

            if let selected, selected.localPath == nil {
                VStack {
                    HStack {
                        Text("本地方案 · 占位")
                            .font(Typo.body(10))
                            .foregroundStyle(Palette.ink2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Palette.bg.opacity(0.72)))
                            .overlay(Capsule().stroke(Palette.line2, lineWidth: 0.5))
                        Spacer()
                    }
                    Spacer()
                }
                .padding(10)
            }

            if isFilling {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(Palette.gold)
                        Text("正在补另外两张…")
                            .font(Typo.body(11))
                            .foregroundStyle(Palette.ink2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.bg.opacity(0.72)))
                    .padding(10)
                }
            }
        }
        .frame(height: 356)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selected == nil ? Palette.line2.opacity(0.7) : Palette.gold.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1, dash: selected == nil ? [7, 6] : []))
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { descFocused = false }
    }

    // MARK: - 候选 / 换一批

    private var candidates: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selected {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selected.title)
                        .font(Typo.body(13, weight: .semibold))
                        .foregroundStyle(Palette.gold)
                    Text(selected.prompt)
                        .font(Typo.body(10.5))
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 10) {
                Text("其他候选")
                    .font(Typo.body(11))
                    .foregroundStyle(Palette.ink3)

                ForEach(plans) { plan in
                    Button {
                        withAnimation(Motion.quick) { selectedID = plan.id }
                    } label: {
                        AgentImage(name: imgName(plan), hue: plan.hue, saturation: plan.saturation)
                            .frame(width: 54, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                if plan.localPath == nil {
                                    Text("本地")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundStyle(Palette.ink3)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Palette.bg.opacity(0.8)))
                                        .padding(3)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(selectedID == plan.id ? Palette.gold : Palette.line2,
                                            lineWidth: selectedID == plan.id ? 1.6 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button { regenerateBatch() } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13))
                        Text("换一批")
                            .font(Typo.body(9.5))
                    }
                    .foregroundStyle(Palette.gold)
                    .frame(width: 54, height: 72)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.gold.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Palette.line2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 描述

    private var describeField: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("形象描述")
                    .font(Typo.body(13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("（可选）")
                    .font(Typo.body(11))
                    .foregroundStyle(Palette.ink3)
                Spacer()
                if descFocused {
                    Button("收键盘") { descFocused = false }
                        .font(Typo.body(11.5))
                        .foregroundStyle(Palette.gold)
                }
            }

            TextEditor(text: $description)
                .focused($descFocused)
                .font(Typo.body(14))
                .foregroundStyle(Palette.ink)
                .scrollContentBackground(.hidden)
                .frame(height: 74)
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.card)
                )
                .overlay(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("五官、动作、服饰、背景…写一句就够")
                            .font(Typo.body(14))
                            .foregroundStyle(Palette.ink3)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 17)
                            .allowsHitTesting(false)
                    }
                }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Text("灵感")
                        .font(Typo.body(11))
                        .foregroundStyle(Palette.ink3)
                    ForEach(ideas, id: \.self) { idea in
                        Button {
                            description = idea
                            descFocused = false
                        } label: {
                            Text(idea)
                                .font(Typo.body(11.5))
                                .foregroundStyle(Palette.ink2)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Palette.card))
                                .overlay(Capsule().stroke(Palette.line2, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 底部按钮

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let failureNote {
                Label(failureNote, systemImage: "exclamationmark.triangle.fill")
                    .font(Typo.body(11))
                    .foregroundStyle(Palette.goldDeep)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            Button {
                descFocused = false
                if let selected {
                    onPick(imgName(selected),
                           selected.localPath == nil ? selected.hue : 0,
                           selected.localPath == nil ? selected.saturation : 1)
                } else {
                    generate()
                }
            } label: {
                HStack(spacing: 7) {
                    if isGenerating {
                        ProgressView().controlSize(.small).tint(Color(hex: 0x2A1F08))
                    }
                    Text(isGenerating ? "正在生成…" : (selected == nil ? "生成图片" : "使用这张"))
                }
            }
            .buttonStyle(GoldButtonStyle(enabled: !isGenerating))
            .disabled(isGenerating)

            if selected != nil {
                Button { regenerateBatch() } label: {
                    Text("不满意？换一张")
                        .font(Typo.body(12.5))
                        .foregroundStyle(Palette.ink3)
                        .frame(maxWidth: .infinity, minHeight: 26)
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            ZStack {
                Color(hex: 0x0A0A12).ignoresSafeArea(edges: .bottom)
                LinearGradient(colors: [Color(hex: 0x0A0A12, alpha: 0), Color(hex: 0x0A0A12)],
                               startPoint: .top, endPoint: .bottom)
                    .padding(.top, -22)
            }
        )
    }

    // MARK: - 行为

    private func imgName(_ plan: VisualPlan) -> String { plan.localPath ?? plan.imageName }

    /// 三张候选给三种景别：全身 / 半身 / 胸像。
    /// 默认第一张是全身立绘——不然模型永远只画一张脸，用户看不到人物全貌。
    private func fullPrompt(for plan: VisualPlan, index: Int) -> String {
        let framing: String
        let english: String
        switch index {
        case 0:
            framing = "角色全身立绘，人物完整站立、从头到脚全部入镜，不裁切，竖构图，人物居中，单人，留出头顶与脚下空间"
            english = "full body shot, head to toe, standing full-length portrait, entire figure visible, vertical composition"
        case 1:
            framing = "角色立绘，半身构图（头顶到腰），人物完整入镜，竖构图，人物居中，单人"
            english = "cowboy shot, head to waist, entire upper body visible, vertical composition"
        default:
            framing = "角色胸像特写，面部细节清晰，眼神有戏，竖构图，单人"
            english = "close-up portrait, detailed face, cinematic expression"
        }
        let subject = "画面主体：\(plan.prompt)，\(english)"
        return hint.isEmpty ? "\(framing)。\(subject)" : "\(hint)。\(framing)。\(subject)"
    }

    private func generate() {
        guard !isGenerating else { return }
        descFocused = false
        failureNote = nil
        isGenerating = true
        isFilling = false
        stageIndex = 0
        generationID += 1
        let myID = generationID

        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let artStyle = style
        let seed = batch
        let base = VisualPlanEngine.plans(for: desc, artStyle: artStyle, seed: seed)
        plans = base
        selectedID = base.first?.id

        // 阶段动画只是氛围，不阻塞真实请求
        let stageTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1100))
                guard stageIndex < stages.count - 1 else { continue }
                stageIndex += 1
            }
        }

        Task {
            let ready = await MainActor.run { LLMSettings.shared.isReady }
            guard ready else {
                stageTask.cancel()
                isGenerating = false
                failureNote = "还没配置生图服务：我的 → 设置 → 模型服务"
                return
            }

            var results = base
            // ① 先出第一张：最快让用户看到结果（原来三张串行，要等 40~90 秒）
            var firstError: String?
            do {
                let path = try await Self.generateWithRetry(fullPrompt(for: base[0], index: 0))
                results[0].localPath = path
            } catch {
                firstError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }

            guard myID == generationID else { return }
            stageTask.cancel()

            if results[0].localPath == nil {
                // 首图就失败：不再连着打后两张（只会把 429 / 断网拖得更糟），
                // 直接把真实原因摊给用户，本地方案标成「占位」而不是假装生成成功
                withAnimation(Motion.smooth) {
                    plans = results
                    selectedID = results.first?.id
                    isGenerating = false
                    isFilling = false
                }
                failureNote = "生图失败：\(firstError ?? "未知原因")，下面是本地方案占位"
                return
            }

            withAnimation(Motion.smooth) {
                plans = results
                selectedID = results[0].id
                isGenerating = false
                isFilling = true
            }

            // ② 剩下两张**串行**补齐：并发容易触发限流（429），
            //    而首图已经能用了，慢一点换稳定更划算
            var extraError: String?
            for index in 1..<base.count {
                guard myID == generationID else { return }
                do {
                    let path = try await Self.generateWithRetry(fullPrompt(for: base[index], index: index))
                    results[index].localPath = path
                    let snapshot = results
                    withAnimation(Motion.quick) { plans = snapshot }
                } catch {
                    extraError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }

            guard myID == generationID else { return }
            withAnimation(Motion.smooth) {
                plans = results
                isFilling = false
                if selectedID == nil { selectedID = results.first?.id }
            }
            if let extraError {
                failureNote = "另外两张没出来（\(extraError)），可以点「换一批」再试"
            }
        }
    }

    /// 生图 + 失败重试一次（429 限流 / 蜂窝抖动都能扛过去）
    private static func generateWithRetry(_ prompt: String) async throws -> String {
        do {
            return try await ImageGenClient.generate(prompt, size: imageSize).localPath
        } catch {
            var retryable = false
            if case ImageGenClient.ImageGenError.http(let code, _) = error {
                retryable = (code == 429 || code >= 500)      // 限流 / 服务端抖动
            }
            if error is URLError { retryable = true }          // 蜂窝断流、TLS 超时
            guard retryable else { throw error }
            try? await Task.sleep(for: .milliseconds(1600))
            return try await ImageGenClient.generate(prompt, size: imageSize).localPath
        }
    }

    private func regenerateBatch() {
        batch += 1
        generate()
    }

    // MARK: - 调试入口（截图/自测用）

    private func runDemoIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-DemoFace") else { return }
        if let i = args.firstIndex(of: "-DemoFaceDesc"), i + 1 < args.count {
            description = args[i + 1]
        } else {
            description = "银发红瞳、一袭黑衣的古风剑客"
        }
        if let i = args.firstIndex(of: "-DemoFaceBatch"), i + 1 < args.count {
            batch = Int(args[i + 1]) ?? 0
        }
        generate()
    }
}
