import SwiftUI

// MARK: - 按钮

struct GoldButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body(16, weight: .semibold))
            .tracking(4)
            .foregroundStyle(enabled ? Color(hex: 0x2A1F08) : Color(hex: 0xD9AE52).opacity(0.6))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                Capsule().fill(
                    enabled
                    ? AnyShapeStyle(Palette.goldGradient)
                    : AnyShapeStyle(Palette.goldDeep.opacity(0.22))
                )
            )
            .shadow(color: enabled ? Palette.goldDeep.opacity(0.28) : .clear, radius: 9, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Palette.ink
    var border: Color = Palette.line2
    var fill: Color = Color.white.opacity(0.04)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body(16, weight: .semibold))
            .tracking(4)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(border, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

struct DarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body(16, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Capsule().fill(Color(hex: 0x111111)))
            .overlay(Capsule().stroke(Palette.line2, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - 图标按钮（44×44 触控目标）

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 21
    var tint: Color = Palette.ink
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemName)
                    .font(.system(size: size, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(width: Spacing.hit, height: Spacing.hit)
                if badge > 0 {
                    Text("\(min(badge, 99))")
                        .font(Typo.body(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Capsule().fill(Palette.danger))
                        .overlay(Capsule().stroke(Palette.bg.opacity(0.9), lineWidth: 1.5))
                        .offset(x: -1, y: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 玻璃卡片

struct GlassCard<Content: View>: View {
    var corner: CGFloat = Radius.md
    var fill: Color = Color(hex: 0x161620).opacity(0.72)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(fill)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

// MARK: - 顶部导航（Task 页通用）

struct NavBar<Trailing: View>: View {
    let title: String
    var showBack: Bool = true
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if showBack {
                Button {
                    onBack?()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: Spacing.hit, height: Spacing.hit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: Spacing.hit)
            }

            Text(title)
                .font(Typo.body(17, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)

            trailing
                .frame(minWidth: Spacing.hit, minHeight: Spacing.hit, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}

extension NavBar where Trailing == EmptyView {
    init(title: String, showBack: Bool = true, onBack: (() -> Void)? = nil) {
        self.init(title: title, showBack: showBack, onBack: onBack) { EmptyView() }
    }
}

// MARK: - 语音波形

struct Waveform: View {
    var color: Color = Palette.pink
    var barWidth: CGFloat = 2.5
    var height: CGFloat = 14
    var animated: Bool = true

    @State private var phase = false

    private let heights: [CGFloat] = [0.36, 0.78, 0.5, 0.95, 0.36]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, ratio in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: height * ratio)
                    .scaleEffect(y: animated ? (phase ? 1.15 : 0.75) : 1, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.85)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.12),
                        value: phase
                    )
            }
        }
        .frame(height: height)
        .onAppear { phase = true }
        .accessibilityHidden(true)
    }
}

// MARK: - 打字指示

struct TypingDots: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(hex: 0x8A8A9E))
                    .frame(width: 6, height: 6)
                    .offset(y: phase ? -4 : 0)
                    .opacity(phase ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.55)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.18),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}

// MARK: - 骨架屏微光

struct ShimmerBlock: View {
    var corner: CGFloat = 8
    var base: Color = Color(hex: 0x1C1C28)
    var highlight: Color = Color(hex: 0x28283A)

    @State private var move = false

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(base)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, highlight, .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: move ? geo.size.width : -geo.size.width * 0.6)
                }
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    move = true
                }
            }
    }
}

// MARK: - 轻提示

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.body(13.5))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                Capsule().fill(Color(hex: 0x1C1C2A).opacity(0.96))
            )
            .overlay(Capsule().stroke(Palette.line2, lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

// MARK: - 活图光效（立绘）：构图完全不动，只有一层柔光极慢地来回流动

struct LivingGlowModifier: ViewModifier {
    /// 光带峰值亮度（很低，只是「活」的感觉）
    var intensity: Double = 0.05
    @State private var forward = false

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    LinearGradient(
                        colors: [.clear, .white.opacity(intensity), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: w * 1.9)
                    .offset(x: forward ? -w * 0.95 : w * 0.95)
                    .blur(radius: 26)
                    // 动画只作用于光带本身——挂在 content 上会把角色切换时
                    // 立绘 frame 的初次布局一起卷进 13s 循环动画（真机上立绘
                    // 会从 0 缓慢"长"到全屏再缩回去），必须隔离在这里。
                    .animation(.easeInOut(duration: 13).repeatForever(autoreverses: true), value: forward)
                }
                .allowsHitTesting(false)
            }
            .onAppear { forward = true }
    }
}

extension View {
    func livingGlow(intensity: Double = 0.05) -> some View {
        modifier(LivingGlowModifier(intensity: intensity))
    }
}
