import SwiftUI

/// 登录 / 注册：手机号 + 密码；注册时走一次短信验证码。
struct LoginView: View {
    /// 以弹窗形式出现时给一个关闭按钮（未登录也能先逛逛）
    var isSheet: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var session = CloudSession.shared

    @State private var mode: Mode = .signIn
    @State private var phone = ""
    @State private var password = ""
    @State private var code = ""
    @State private var verificationId = ""
    @State private var countdown = 0
    @State private var busy = false
    @State private var error = ""
    @State private var hint = ""

    private enum Mode: String, CaseIterable {
        case signIn = "登录"
        case register = "注册"
    }

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if isSheet {
                        HStack {
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.ink2)
                                    .frame(width: 32, height: 32)
                                    .background(Color.white.opacity(0.08), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("稍后再说")
                        }
                    }
                    header
                    modePicker
                    fields
                    if !hint.isEmpty {
                        Text(hint)
                            .font(Typo.body(12))
                            .foregroundStyle(Palette.gold.opacity(0.9))
                    }
                    if !error.isEmpty {
                        Text(error)
                            .font(Typo.body(12))
                            .foregroundStyle(Color(hex: 0xE5484D))
                    }
                    primaryButton
                    Text("继续即表示同意《用户协议》与《隐私政策》。手机号只用于登录，不会展示给其他用户。")
                        .font(Typo.body(10.5))
                        .foregroundStyle(Palette.ink3.opacity(0.8))
                        .lineSpacing(3)
                }
                .padding(.horizontal, 26)
                .padding(.top, 90)
                .padding(.bottom, 40)
            }
        }
        .background(Palette.bg)
        .onChange(of: mode) { _, _ in
            error = ""
            hint = ""
        }
    }

    private var background: some View {
        ZStack {
            Palette.bg
            Circle()
                .fill(Palette.gold.opacity(0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: 120, y: -220)
            Circle()
                .fill(Color(hex: 0x3A4B8F).opacity(0.25))
                .frame(width: 360, height: 360)
                .blur(radius: 110)
                .offset(x: -140, y: 320)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("夜谈")
                .font(Typo.display(34))
                .tracking(8)
                .foregroundStyle(Palette.ink)
            Text("深夜有人接你的电话")
                .font(Typo.body(13))
                .foregroundStyle(Palette.ink3)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(Mode.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { mode = item }
                } label: {
                    Text(item.rawValue)
                        .font(Typo.body(13, weight: mode == item ? .semibold : .regular))
                        .foregroundStyle(mode == item ? Color(hex: 0x101018) : Palette.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if mode == item {
                                Capsule().fill(Palette.gold)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Palette.card, in: Capsule())
        .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
    }

    private var fields: some View {
        VStack(spacing: 12) {
            field("手机号") {
                TextField("11 位手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .foregroundStyle(Palette.ink)
                    .font(Typo.body(15))
            }

            if mode == .register {
                field("验证码") {
                    HStack(spacing: 10) {
                        TextField("6 位数字", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .foregroundStyle(Palette.ink)
                            .font(Typo.body(15))
                        Button(countdown > 0 ? "\(countdown)s" : "获取验证码") {
                            Task { await sendCode() }
                        }
                        .font(Typo.body(12, weight: .semibold))
                        .foregroundStyle(countdown > 0 ? Palette.ink3 : Palette.gold)
                        .disabled(countdown > 0 || busy)
                    }
                }
            }

            field(mode == .signIn ? "密码" : "设置密码") {
                SecureField("至少 6 位", text: $password)
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .foregroundStyle(Palette.ink)
                    .font(Typo.body(15))
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typo.body(10.5))
                .foregroundStyle(Palette.ink3.opacity(0.8))
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Palette.line, lineWidth: 1)
                )
        }
    }

    private var primaryButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(Color(hex: 0x101018)) }
                Text(mode == .signIn ? "登录" : "注册并登录")
                    .font(Typo.body(15, weight: .semibold))
            }
            .foregroundStyle(Color(hex: 0x101018))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Palette.gold, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.7 : 1)
    }

    // MARK: 动作

    private func sendCode() async {
        error = ""
        hint = ""
        let number = phone.trimmingCharacters(in: .whitespaces)
        guard number.count == 11 else {
            error = "手机号格式不对"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let result = try await session.sendCode(phone: number)
            verificationId = result.verificationId
            countdown = 60
            if result.existing {
                // 已经注册过：直接切登录，省一步
                hint = "这个号码已经注册过了，输密码登录就行"
                mode = .signIn
            } else {
                hint = "验证码已发出，注意查收短信"
            }
            Task { await tick() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func tick() async {
        while countdown > 0 {
            try? await Task.sleep(for: .seconds(1))
            countdown -= 1
        }
    }

    private func submit() async {
        error = ""
        let number = phone.trimmingCharacters(in: .whitespaces)
        guard number.count == 11 else {
            error = "手机号格式不对"
            return
        }
        guard password.count >= 6 else {
            error = "密码至少 6 位"
            return
        }
        busy = true
        defer { busy = false }
        do {
            if mode == .signIn {
                try await session.signIn(phone: number, password: password)
            } else {
                guard !verificationId.isEmpty else {
                    error = "先点「获取验证码」"
                    return
                }
                let token = try await session.verifyCode(verificationId: verificationId,
                                                         code: code.trimmingCharacters(in: .whitespaces))
                try await session.register(phone: number, verificationToken: token, password: password)
            }
            if isSheet { dismiss() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
