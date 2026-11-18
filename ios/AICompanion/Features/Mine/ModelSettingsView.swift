import SwiftUI

/// 对话模型设置：把本地人设 Mock 换成真实大模型（OpenAI 兼容协议）
struct ModelSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var settings = LLMSettings.shared
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "对话模型", onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    providerCard
                    formCard
                    testCard
                    guideCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.canvas)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: 状态

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: settings.isReady ? "sparkles" : "person.wave.2")
                    .font(.system(size: 24))
                    .foregroundStyle(settings.isReady ? Palette.gold : Palette.ink2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.isReady ? "真实模型已启用" : "本地人设模式")
                        .font(Typo.body(15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(settings.statusText)
                        .font(Typo.body(11.5))
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { settings.isEnabled },
                    set: { settings.isEnabled = $0 }
                ))
                .labelsHidden()
                .tint(Palette.goldDeep)
            }

            Text(settings.isReady
                 ? "角色回复将由大模型实时生成，人设、语气、亲密度和跨会话记忆都会写进系统提示词。"
                 : "当前回复由 App 内置的人设台词引擎生成（离线、免费、可演示）。填好下方配置并打开开关，即可换成真实模型。")
                .font(Typo.body(11.5))
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
        )
    }

    // MARK: 服务商

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("服务商", subtitle: "全部走 OpenAI 兼容协议，随时可换")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LLMProvider.allCases) { provider in
                        Button {
                            settings.provider = provider
                            testResult = nil
                        } label: {
                            Text(provider.shortTitle)
                                .font(Typo.body(12.5, weight: .medium))
                                .foregroundStyle(settings.provider == provider ? Color(hex: 0x101018) : Palette.ink)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(settings.provider == provider
                                                   ? AnyShapeStyle(Palette.fabGradient)
                                                   : AnyShapeStyle(Palette.bg))
                                )
                                .overlay(Capsule().stroke(Palette.line, lineWidth: settings.provider == provider ? 0 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            Text(settings.provider.note)
                .font(Typo.body(11))
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
        )
    }

    // MARK: 表单

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("连接参数", subtitle: settings.provider.needsManualBaseURL ? "本机/自定义需要手动填地址" : "已自动填好，通常只需补 API Key")

            field("服务地址", text: Binding(
                get: { settings.baseURL },
                set: { settings.baseURL = $0 }
            ), placeholder: "https://…/v1", secret: false)

            field("模型名", text: Binding(
                get: { settings.model },
                set: { settings.model = $0 }
            ), placeholder: "glm-4-flash", secret: false)

            if settings.provider.needsKey {
                field("API Key", text: Binding(
                    get: { settings.apiKey },
                    set: { settings.apiKey = $0 }
                ), placeholder: "粘贴你的 Key（只存本机 Keychain）", secret: true)
            } else {
                Text("本机 Ollama 不需要 Key。先在 Mac 执行：\nollama serve  →  ollama pull \(settings.model)")
                    .font(Typo.body(11.5))
                    .foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Key 只保存在本机 Keychain，不上传任何服务器；聊天请求直接从手机发往你选的模型服务。")
                .font(Typo.body(10.5))
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
        )
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String, secret: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Typo.body(11))
                .foregroundStyle(Palette.ink3)
            Group {
                if secret {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(Typo.body(13))
            .foregroundStyle(Palette.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
            )
        }
    }

    // MARK: 测试

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                runTest()
            } label: {
                HStack(spacing: 7) {
                    if testing {
                        ProgressView().tint(Color(hex: 0x101018)).scaleEffect(0.8)
                    } else {
                        Image(systemName: "bolt.horizontal.circle")
                    }
                    Text(testing ? "正在请求模型…" : "测试连接")
                }
                .font(Typo.body(13.5, weight: .medium))
                .foregroundStyle(Color(hex: 0x101018))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.fabGradient)
                )
            }
            .buttonStyle(.plain)
            .disabled(testing || !settings.config.isUsable)

            if let testResult {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: testOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(testOK ? Palette.ok : Palette.danger)
                    Text(testResult)
                        .font(Typo.body(11.5))
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
        )
    }

    private func runTest() {
        testing = true
        testResult = nil
        let config = settings.config
        Task {
            let result = await LLMProbe.test(config)
            await MainActor.run {
                testing = false
                switch result {
                case let .success(text):
                    testOK = true
                    testResult = "连接成功，模型回了：\(text)"
                case let .failure(error):
                    testOK = false
                    testResult = "失败：\(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: 指引

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("怎么拿到 Key", systemImage: "key.horizontal")
                .font(Typo.body(13, weight: .semibold))
                .foregroundStyle(Palette.ink)
            note("智谱：open.bigmodel.cn → API Keys，glm-4-flash 免费")
            note("DeepSeek：platform.deepseek.com → API keys")
            note("百炼：bailian.console.aliyun.com → API-KEY，qwen-flash 有免费额度")
            note("本机 Ollama：Mac 上执行 ollama serve，再 ollama pull \(settings.model)；手机与 Mac 同一 Wi-Fi，地址填 Mac 局域网 IP")
            Divider().overlay(Palette.line).padding(.vertical, 2)
            note("当前角色库、点赞数仍是 App 内置演示数据；要改成运营后台下发，需要接一个 /v1/agents 接口。")
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

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typo.body(11.5))
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionTitle(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typo.body(13, weight: .semibold))
                .foregroundStyle(Palette.ink)
            if let subtitle {
                Text(subtitle)
                    .font(Typo.body(11))
                    .foregroundStyle(Palette.ink3)
            }
        }
        .padding(.bottom, 2)
    }
}
