import AVFoundation
import SwiftUI
import UIKit

/// 语音引擎设置：本地 edge-tts 服务（免费、无 Key、无云端请求）
struct VoiceSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var settings = VoiceSettings.shared
    @ObservedObject private var voice = VoiceService.shared
    @State private var previewer = PreviewPlayer()
    @State private var checking = false
    @State private var tencent = TencentVoiceSettings.shared
    @State private var txSecretId = ""
    @State private var txSecretKey = ""
    @State private var txMessage: String?
    @State private var txTesting = false
    @State private var sysSynth = AVSpeechSynthesizer()
    @State private var diagRunning = false
    @State private var diagResult: String?
    @State private var azure = AzureVoiceSettings.shared
    @State private var azureKey = ""
    @State private var azureRegion = ""
    @State private var azureMessage: String?
    @State private var azureTesting = false
    @State private var azurePreview: AVAudioPlayer?
    @State private var breeze = BreezeVoiceSettings.shared
    @State private var breezeKey = ""
    @State private var breezeMessage: String?
    @State private var breezeTesting = false
    @State private var breezePreview: AVAudioPlayer?

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Palette.bg)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
            )
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "语音引擎", onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    breezeCard
                    tencentCard
                    if azure.isConfigured { azureCard }
                    systemVoiceCard
                    setupNote
                    voiceCard
                    addressCard
                    footnote
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
        .onAppear { voice.refreshServerStatus() }
        .onDisappear { previewer.stop() }
    }

    // MARK: 状态卡

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(voice.isLocalServerUp || breeze.hasKey ? Palette.ok : Palette.goldDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("语音引擎状态")
                        .font(Typo.body(15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(statusText)
                        .font(Typo.body(11.5))
                        .foregroundStyle(voice.isLocalServerUp ? Palette.ok : Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                CircleIconButton(systemName: "arrow.clockwise") {
                    checking = true
                    voice.refreshServerStatus()
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        checking = false
                    }
                }
                .disabled(checking)
            }

            Text(breeze.hasKey && breeze.enabled
                 ? "聊天语音条：BreezeBlue 角色音色（失败回退本地/云端）；通话：本地 → Azure → 腾讯 → 系统"
                 : (azure.isConfigured
                    ? "四层引擎：Mac 本地服务 → Azure 云扬 → 腾讯云 → 设备内置（离线兜底）"
                    : "三层引擎：Mac 本地服务 → 腾讯云（4G 可用）→ 设备内置（离线兜底）"))
                .font(Typo.body(11.5))
                .foregroundStyle(Palette.ink2)

            Button {
                runDiagnosis()
            } label: {
                HStack(spacing: 6) {
                    if diagRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "stethoscope")
                    }
                    Text(diagRunning ? "诊断中…" : "一键诊断（结果自动复制到剪贴板）")
                }
                .font(Typo.body(12, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .stroke(Palette.line, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            if let diagResult {
                Text(diagResult)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Palette.bg)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
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

    private var statusText: String {
        if breeze.hasKey && breeze.enabled {
            return "聊天语音条优先 BreezeBlue · 最近播放：\(voice.lastEngine)"
        }
        if voice.isLocalServerUp { return "高音质引擎已连接 · 当前 \(voice.lastEngine)" }
        if let error = voice.lastError, !error.isEmpty {
            return "云端合成失败，已降级为内置语音：\(error)"
        }
        if azure.isConfigured { return "当前走 Azure 云扬（4G / Wi-Fi 均可）· 已播放：\(voice.lastEngine)" }
        if tencent.isConfigured { return "当前走腾讯云语音（Wi-Fi / 蜂窝均可）· 已播放：\(voice.lastEngine)" }
        return "请在下方填写腾讯云凭证，蜂窝数据下即可用云端语音"
    }

    // MARK: 腾讯云语音（云端引擎）

    private var tencentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(tencent.isConfigured ? Palette.ok : Palette.goldDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("云端语音 · 腾讯云（免费额度）")
                        .font(Typo.body(14.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(tencent.isConfigured
                         ? "已配置，Wi-Fi / 蜂窝均可播放 14 种角色音色"
                         : "未配置——填写后可脱离 Mac、用蜂窝数据播放")
                        .font(Typo.body(11))
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                TextField("", text: $txSecretId,
                          prompt: Text("SecretId（已内置，可留空）").foregroundStyle(Palette.ink3))
                    .textFieldStyle(.plain)
                    .font(Typo.body(13.5))
                    .foregroundStyle(Palette.ink)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(11)
                    .background(inputBackground)

                if tencent.usesBundledId {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                        Text("SecretId 已内置，你只需粘贴 SecretKey")
                            .font(Typo.body(11))
                    }
                    .foregroundStyle(Palette.ok)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SecureField("", text: $txSecretKey,
                            prompt: Text(tencent.hasSecretKey ? "SecretKey（已保存，留空则不修改）" : "SecretKey（粘贴到这里）")
                                .foregroundStyle(Palette.ink3))
                    .textFieldStyle(.plain)
                    .font(Typo.body(13.5))
                    .foregroundStyle(Palette.ink)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(11)
                    .background(inputBackground)
            }

            HStack(spacing: 10) {
                Button {
                    saveAndTestTencent()
                } label: {
                    HStack(spacing: 6) {
                        if txTesting {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(txTesting ? "测试中…" : "保存并测试")
                    }
                    .font(Typo.body(13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(txTesting ? Palette.ink3 : Palette.goldDeep)
                    )
                }
                .buttonStyle(.plain)
                .disabled(txTesting)

                if tencent.isConfigured {
                    Button {
                        tencent.clear()
                        txSecretId = ""
                        txSecretKey = ""
                        txMessage = "已清除凭证"
                    } label: {
                        Text("清除")
                            .font(Typo.body(13))
                            .foregroundStyle(Palette.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .stroke(Palette.line2, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let txMessage {
                Text(txMessage)
                    .font(Typo.body(11.5))
                    .foregroundStyle(txMessage.hasPrefix("✅") ? Palette.ok : Palette.goldDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("获取方式（一次配置，永久生效）")
                    .font(Typo.body(11.5, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                noteRow("① 控制台领取「语音合成」免费资源包（800 万字符）")
                noteRow("② 访问管理 → API 密钥管理 → 新建密钥，复制 SecretKey")
                noteRow("③ SecretId 已内置，只需把 SecretKey 粘到上面第二个框")
                noteRow("④ 点「保存并测试」，显示 ✅ 即蜂窝数据下也能播放")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(tencent.isConfigured ? Palette.ok.opacity(0.5) : Palette.line, lineWidth: 1)
        )
        .onAppear { txSecretId = tencent.usesBundledId ? "" : tencent.secretId }
    }

    private func saveAndTestTencent() {
        guard !txTesting else { return }
        let id = txSecretId.trimmingCharacters(in: .whitespaces)
        // SecretId 留空 = 用内置值
        tencent.save(secretId: id, secretKey: txSecretKey)
        txSecretKey = ""
        guard tencent.isConfigured else {
            txMessage = "请粘贴 SecretKey（SecretId 已内置，无需填写）"
            return
        }
        txTesting = true
        txMessage = nil
        Task {
            do {
                _ = try await TencentTTSClient.synthesize(text: "你好，我是你的角色，这种声音你觉得如何？", kind: .warmFemale)
                txMessage = "✅ 云端语音已连通，蜂窝数据下也能正常播放"
            } catch {
                txMessage = error.localizedDescription
            }
            txTesting = false
        }
    }

    // MARK: Azure 神经语音（云扬）

    private var breezeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(breeze.hasKey ? Palette.ok : Palette.goldDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BreezeBlue 角色音色")
                        .font(Typo.body(14.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(breeze.hasKey
                         ? "已配置 · 苏晚棠「迷糊版」、沈惊寒「幽巷引路人」；通话仍走本地"
                         : "聊天语音条改用角色专属音色；通话仍走本地，不增加等待")
                        .font(Typo.body(11))
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            SecureField("", text: $breezeKey,
                        prompt: Text(breeze.hasKey ? "Key（已保存，留空则不修改）" : "粘贴 BreezeBlue API Key（brz_...）")
                            .foregroundStyle(Palette.ink3))
                .textFieldStyle(.plain)
                .font(Typo.body(13.5))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(11)
                .background(inputBackground)

            Toggle(isOn: Binding(
                get: { breeze.enabled },
                set: { breeze.enabled = $0 }
            )) {
                Text("聊天语音条优先使用 BreezeBlue")
                    .font(Typo.body(12.5))
                    .foregroundStyle(Palette.ink2)
            }
            .tint(Palette.goldDeep)

            HStack(spacing: 10) {
                Button {
                    saveAndTestBreeze()
                } label: {
                    HStack(spacing: 6) {
                        if breezeTesting {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(breezeTesting ? "测试中…" : "保存并试听")
                    }
                    .font(Typo.body(13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(breezeTesting ? Palette.ink3 : Palette.goldDeep)
                    )
                }
                .buttonStyle(.plain)
                .disabled(breezeTesting)

                if breeze.hasKey {
                    Button {
                        breeze.clear()
                        breezeKey = ""
                        breezeMessage = "已清除 BreezeBlue Key"
                    } label: {
                        Text("清除")
                            .font(Typo.body(13))
                            .foregroundStyle(Palette.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .stroke(Palette.line2, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let breezeMessage {
                Text(breezeMessage)
                    .font(Typo.body(11.5))
                    .foregroundStyle(breezeMessage.hasPrefix("✅") ? Palette.ok : Palette.goldDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let err = voice.lastBreezeError, !err.isEmpty {
                Text("Breeze 最近一次失败：\(err)")
                    .font(Typo.body(11.5))
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("怎么拿 Key")
                    .font(Typo.body(11.5, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                noteRow("① breezeblue.ai 首页 → 创建 API Key")
                noteRow("② 积分上限填 1000，复制 brz_...（只显示一次）")
                noteRow("③ 粘贴到这里，点「保存并试听」")
            }
        }
        .padding(16)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func saveAndTestBreeze() {
        guard !breezeTesting else { return }
        if !breezeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            breeze.save(key: breezeKey)
        }
        breezeKey = ""
        guard breeze.hasKey else {
            breezeMessage = "请粘贴 BreezeBlue API Key（brz_...）"
            return
        }
        breezeTesting = true
        breezeMessage = nil
        Task { @MainActor in
            do {
                let entry = BreezeVoiceCast.byCharacterID["swt"]
                    ?? BreezeVoiceCast.Entry(name: "大肥鱼·迷糊版", voiceID: "voc_8yud7hz7c9q2")
                let url = try await BreezeTTSClient.synthesize(
                    text: "呜哇，被你发现啦！我在认真思考呢，才没有摸鱼。",
                    entry: entry
                )
                breezeMessage = "✅ 已连通，下面是苏晚棠的试听"
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, options: [.duckOthers])
                try? session.setActive(true)
                breezePreview = try? AVAudioPlayer(contentsOf: url)
                breezePreview?.play()
            } catch {
                breezeMessage = error.localizedDescription
            }
            breezeTesting = false
        }
    }

    private var azureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(azure.isConfigured ? Palette.ok : Palette.goldDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("云端语音 · 微软 Azure（云扬音色）")
                        .font(Typo.body(14.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(azure.isConfigured
                         ? "已配置 · 沈惊寒等男角色会用「云扬」低沉朗读"
                         : "推荐先用这个：每月 50 万字符免费，音色最像古风男声")
                        .font(Typo.body(11))
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            SecureField("", text: $azureKey,
                        prompt: Text(azure.hasKey ? "Key（已保存，留空则不修改）" : "粘贴 Azure 语音服务 Key")
                            .foregroundStyle(Palette.ink3))
                .textFieldStyle(.plain)
                .font(Typo.body(13.5))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(11)
                .background(inputBackground)

            TextField("", text: $azureRegion,
                      prompt: Text("区域，如 eastasia（留空用 \(azure.region)）").foregroundStyle(Palette.ink3))
                .textFieldStyle(.plain)
                .font(Typo.body(13.5))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(11)
                .background(inputBackground)

            HStack(spacing: 10) {
                Button {
                    saveAndTestAzure()
                } label: {
                    HStack(spacing: 6) {
                        if azureTesting {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(azureTesting ? "测试中…" : "保存并试听云扬")
                    }
                    .font(Typo.body(13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(azureTesting ? Palette.ink3 : Palette.goldDeep)
                    )
                }
                .buttonStyle(.plain)
                .disabled(azureTesting)

                if azure.isConfigured {
                    Button {
                        azure.clear()
                        azureKey = ""
                        azureMessage = "已清除 Azure Key"
                    } label: {
                        Text("清除")
                            .font(Typo.body(13))
                            .foregroundStyle(Palette.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .stroke(Palette.line2, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let azureMessage {
                Text(azureMessage)
                    .font(Typo.body(11.5))
                    .foregroundStyle(azureMessage.hasPrefix("✅") ? Palette.ok : Palette.goldDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("获取方式（一次配置，永久生效，F0 免费层每月 50 万字符）")
                    .font(Typo.body(11.5, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                noteRow("① 打开 portal.azure.com → 搜索「语音服务 Speech」→ 创建")
                noteRow("② 定价层一定选「免费 F0」，区域建议 eastasia")
                noteRow("③ 创建完成后进资源 → 密钥和终结点 → 复制 KEY 1")
                noteRow("④ 粘贴 Key 和区域，点「保存并试听云扬」")
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(azure.isConfigured ? Palette.goldDeep.opacity(0.5) : Palette.line, lineWidth: 1)
        )
    }

    private func saveAndTestAzure() {
        guard !azureTesting else { return }
        azure.save(key: azureKey, region: azureRegion)
        azureKey = ""
        azureRegion = ""
        guard azure.isConfigured else {
            azureMessage = "请粘贴 Azure 语音服务 Key（区域默认 eastasia）"
            return
        }
        azureTesting = true
        azureMessage = nil
        Task { @MainActor in
            do {
                let url = try await AzureTTSClient.synthesize(
                    text: "夜深了。这宫里的人都在睡，只有我醒着——等你。",
                    kind: .deepMale
                )
                azureMessage = "✅ 云扬已连通，下面是沈惊寒的试听"
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, options: [.duckOthers])
                try? session.setActive(true)
                azurePreview = try? AVAudioPlayer(contentsOf: url)
                azurePreview?.play()
            } catch {
                azureMessage = error.localizedDescription
            }
            azureTesting = false
        }
    }

    // MARK: 设备内置语音（离线兜底）

    private var systemVoiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.ok)
                VStack(alignment: .leading, spacing: 2) {
                    Text("设备内置语音 · 随时可用")
                        .font(Typo.body(14.5, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(SystemVoiceCatalog.summary())
                        .font(Typo.body(11))
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(SystemVoiceCatalog.chinese().prefix(6))) { option in
                    HStack {
                        Text(option.name)
                            .font(Typo.body(13))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(option.isMale ? "男声" : "女声")
                            .font(Typo.body(10.5))
                            .foregroundStyle(Palette.ink3)
                        Text(option.qualityLabel)
                            .font(Typo.body(10.5))
                            .foregroundStyle(option.quality >= 2 ? Palette.ok : Palette.ink3)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().stroke(Palette.line, lineWidth: 1))
                            .padding(.leading, 6)
                    }
                    .padding(.vertical, 7)
                }
            }

            if let male = SystemVoiceCatalog.best(for: .deepMale) {
                Text("男角色当前使用：\(male.name)")
                    .font(Typo.body(11))
                    .foregroundStyle(Palette.ink3)
            }

            Button {
                speakSystemPreview()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.circle")
                    Text("试听内置男声（断网也能听）")
                }
                .font(Typo.body(12.5, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .stroke(Palette.line, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            Button {
                openSystemVoiceSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                    Text("去系统里下载男声「李牧」（免费）")
                }
                .font(Typo.body(12.5, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.goldDeep)
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("① 设置 → 辅助功能 → 朗读内容 → 声音 → 中文 → 普通话")
                Text("② 找到「李牧」或「瀚」「彬彬」等男声 → 点 ▶ 可先试听")
                Text("③ 点「优化音质」右侧 ⬇️ 下载（免费，需 Wi-Fi）")
                Text("下载后男角色离线也是真男声，音质接近云端神经语音。")
                    .foregroundStyle(Palette.ink3)
            }
            .font(Typo.body(11))
            .foregroundStyle(Palette.ink2)
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

    /// 一键诊断：跑完三层引擎链路，结果展示并复制到剪贴板
    private func runDiagnosis() {
        guard !diagRunning else { return }
        diagRunning = true
        diagResult = nil
        Task { @MainActor in
            var lines: [String] = ["【夜谈语音诊断】"]
            // ① Mac 本地服务
            do {
                try await VoiceSettings.shared.client.health()
                lines.append("① Mac 本地服务：可达（App 会优先用它）")
            } catch {
                lines.append("① Mac 本地服务：不可达（4G 下正常，走云端）")
            }
            // ② Azure 云扬（仅在已配置时检查）
            if azure.isConfigured {
                do {
                    let start = Date()
                    _ = try await AzureTTSClient.synthesize(
                        text: "夜深了，有些话只想说给你一个人听。", kind: .deepMale)
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    lines.append("② Azure 云扬（沈惊寒）：合成成功，耗时 \(ms) ms")
                } catch {
                    lines.append("② Azure 云扬（沈惊寒）：失败 → \(error.localizedDescription)")
                }
            }
            // ③ 腾讯云端（沉金男声，沈惊寒同款）
            let start = Date()
            do {
                _ = try await TencentTTSClient.synthesize(
                    text: "夜深了，有些话只想说给你一个人听。",
                    kind: .deepMale
                )
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                lines.append("③ 腾讯云端（沉金男声）：合成成功，耗时 \(ms) ms")
            } catch {
                lines.append("③ 腾讯云端（沉金男声）：失败 → \(error.localizedDescription)")
            }
            // ④ 内置兜底音色
            if let v = SystemVoiceCatalog.best(for: .deepMale) {
                let q = v.quality.rawValue >= 3 ? "高级" : (v.quality.rawValue >= 2 ? "增强" : "标准")
                let gender = SystemVoiceCatalog.isMaleVoice(v) ? "男声" : "女声"
                lines.append("④ 内置兜底音色：\(v.name)（\(gender)·\(q)）")
            }
            // ⑤ 当前状态
            lines.append("⑤ 当前引擎：\(voice.lastEngine)")
            if let e = voice.lastError, !e.isEmpty {
                lines.append("⑥ 最近一次错误：\(e)")
            }
            let report = lines.joined(separator: "\n")
            UIPasteboard.general.string = report
            diagResult = report
            diagRunning = false
        }
    }

    /// 试听设备内置男声：用的就是聊天里断网兜底时的同一套挑选逻辑
    private func speakSystemPreview() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers])
        try? session.setActive(true)
        if sysSynth.isSpeaking { sysSynth.stopSpeaking(at: .immediate) }
        let voice = SystemVoiceCatalog.best(for: .deepMale)
        let utterance = AVSpeechUtterance(string: "夜深了，你还没睡？有些话，我只想说给你一个人听。")
        utterance.voice = voice
        utterance.pitchMultiplier = SystemVoiceCatalog.isMaleVoice(voice) ? 0.95 : 0.82
        utterance.rate = VoiceKind.deepMale.rate
        sysSynth.speak(utterance)
        store.showToast(voice.map { "内置音色：\($0.name)" } ?? "内置音色：系统默认")
    }

    private func openSystemVoiceSettings() {
        // 私有 URL scheme 在新系统上经常失效（返回成功但落在通用页），
        // 所以按成功率依次尝试多个变体，全部被拒时兜底打开本 App 设置页并提示手动路径。
        let candidates = [
            "App-Prefs:root=ACCESSIBILITY&path=SPEECH_TITLE", // 新版：朗读内容
            "App-Prefs:root=ACCESSIBILITY&path=SPEECH",       // 旧版：朗读内容
            "App-Prefs:root=ACCESSIBILITY"                    // 退而求其次：辅助功能
        ]
        var pending = candidates
        func tryNext() {
            guard let next = pending.first else {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url, options: [:])
                }
                store.showToast("未能直达，请手动进入：设置 → 辅助功能 → 朗读内容 → 声音 → 中文（普通话）")
                return
            }
            pending.removeFirst()
            guard let url = URL(string: next) else { tryNext(); return }
            UIApplication.shared.open(url, options: [:]) { ok in
                if !ok { tryNext() }
            }
        }
        tryNext()
    }

    // MARK: 启动说明

    private var setupNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("如何使用", systemImage: "questionmark.circle")
                .font(Typo.body(13, weight: .semibold))
                .foregroundStyle(Palette.ink)
            noteRow("① 有声音就能用：不开 Mac、不联网也会用设备内置语音朗读")
            noteRow("② 想要更好的音质：Mac 上执行 bash ios/tools/start-tts.sh，App 会自动切到神经音色")
            noteRow("③ 真机首次会弹「本地网络」权限；自动发现失败时把下方地址改成 Mac 局域网 IP（Mac 终端输入 ipconfig getifaddr en0 查看）")
            noteRow("④ 两套引擎自动切换，任何情况下 App 都不会哑掉")
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

    private func noteRow(_ text: String) -> some View {
        Text(text)
            .font(Typo.body(12))
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 音色表（四种人格气质 → 微软神经音色）

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("角色音色", subtitle: "微软神经语音，与本地离线语音包同源")
            ForEach(VoiceKind.allCases, id: \.self) { kind in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.rawValue)
                            .font(Typo.body(14))
                            .foregroundStyle(Palette.ink)
                        Text(kind.edgeVoice)
                            .font(Typo.body(11))
                            .foregroundStyle(Palette.ink3)
                    }
                    Spacer()
                    CircleIconButton(
                        systemName: previewer.isPlaying && previewer.tag == kind.rawValue ? "stop.circle" : "play.circle"
                    ) {
                        let sample: String
                        switch kind.gender {
                        case "儿童": sample = "你好呀，我叫小豆丁，今天也可以一起玩吗？"
                        case "女": sample = "你好呀，今天想聊点什么？我在这儿听着呢。"
                        default: sample = "你好，我在。有什么想说的，慢慢讲。"
                        }
                        previewer.toggle(
                            text: sample,
                            voice: kind.edgeVoice,
                            rate: kind.edgeRate,
                            pitch: kind.edgePitch,
                            tag: kind.rawValue,
                            kind: kind
                        )
                    }
                }
                .padding(.vertical, 10)
                if kind != VoiceKind.allCases.last {
                    Divider().overlay(Palette.line)
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

    // MARK: 服务地址

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("服务地址", subtitle: "真机改为 Mac 局域网 IP")
            HStack(spacing: 8) {
                TextField("http://127.0.0.1:9880", text: $settings.baseURLString)
                    .font(Typo.body(13.5))
                    .foregroundStyle(Palette.ink)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        voice.refreshServerStatus()
                        store.showToast("正在检测 \(settings.baseURLString)")
                    }
                CircleIconButton(systemName: "arrow.clockwise") {
                    voice.refreshServerStatus()
                    store.showToast("正在检测 \(settings.baseURLString)")
                }
            }
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
        .padding(16)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
        )
    }

    private var footnote: some View {
        Text("本引擎完全免费：edge-tts 为微软公开神经音色，合成只经过你的 Mac，无账号、无计费、无配额。")
            .font(Typo.body(11))
            .foregroundStyle(Palette.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 通用小组件

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
        .padding(.bottom, 10)
    }
}

// MARK: - 设置页试听播放器

@MainActor
@Observable
final class PreviewPlayer: NSObject {
    private(set) var isPlaying = false
    private(set) var tag: String?
    /// 最近一次失败原因（合成失败 = 服务不可达，回退系统语音）
    private(set) var lastError: String?
    private var player: AVAudioPlayer?
    private var task: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()

    func toggle(text: String, voice: String, rate: String, pitch: String, tag: String, kind: VoiceKind) {
        if isPlaying && self.tag == tag {
            stop()
            return
        }
        stop()
        self.tag = tag
        isPlaying = true
        lastError = nil
        let spoken = VoiceService.spokenPart(of: text)
        sampleText = spoken.isEmpty ? text : spoken
        task = Task { [weak self] in
            // Mac 本地服务已知不可达（蜂窝/服务没开）时直接走云端，
            // 不再先空等 8 秒超时——之前点试听要干等 10 秒才有声，被当成「没有声音」
            if VoiceService.shared.isLocalServerUp {
                do {
                    let url = try await LocalTTSAudioCache.shared.audioURL(
                        text: spoken,
                        voice: voice, rate: rate, pitch: pitch,
                        client: VoiceSettings.shared.client
                    )
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard let self, self.tag == tag else { return }
                        // 本地 edge-tts 语速已在合成阶段定好，播放端原速
                        self.play(url: url, rate: 1.0)
                    }
                    return
                } catch is CancellationError {
                    await MainActor.run {
                        if let self, self.tag == tag { self.isPlaying = false }
                    }
                    return
                } catch {
                    // 本地合成失败 → 落到下面的云端链路
                }
            }
            // 云端（蜂窝也能用）→ 云端也失败才用设备内置
            if let cloudURL = try? await TencentTTSClient.synthesize(text: spoken, kind: kind) {
                await MainActor.run {
                    guard let self, self.tag == tag else { return }
                    if !VoiceService.shared.isLocalServerUp {
                        self.lastError = "Mac 未连接，本条为云端语音试听"
                    }
                    self.play(url: cloudURL, rate: kind.cloudRate)
                }
            } else {
                await MainActor.run {
                    self?.lastError = "网络不可用，本条为设备内置语音试听"
                    self?.speakWithSystemFallback(spoken, kind: kind)
                }
            }
        }
    }

    /// 大肥鱼音色试听：直接走 Breeze，不再用 edge/腾讯的近似音色
    func toggleBreeze(text: String, entry: BreezeVoiceCast.Entry, tag: String) {
        if isPlaying && self.tag == tag {
            stop()
            return
        }
        stop()
        self.tag = tag
        isPlaying = true
        lastError = nil
        let spoken = VoiceService.spokenPart(of: text)
        let sampleText = spoken.isEmpty ? text : spoken
        task = Task { [weak self] in
            do {
                let url = try await BreezeTTSClient.synthesize(text: sampleText, entry: entry)
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self, self.tag == tag else { return }
                    self.play(url: url, rate: 1.0)
                }
            } catch is CancellationError {
                await MainActor.run {
                    if let self, self.tag == tag { self.isPlaying = false }
                }
            } catch {
                await MainActor.run {
                    guard let self, self.tag == tag else { return }
                    self.lastError = "Breeze 试听失败：\(error.localizedDescription)"
                    self.isPlaying = false
                }
            }
        }
    }

    /// 服务不可达时的设备内置语音兜底（音色按角色气质挑选）
    private func speakWithSystemFallback(_ text: String, kind: VoiceKind) {
        guard !text.isEmpty else { stop(); return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.duckOthers])
        try? session.setActive(true)
        let selected = SystemVoiceCatalog.best(for: kind)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selected
        let isMaleRole = kind.gender == "男"
        utterance.pitchMultiplier = SystemVoiceCatalog.isMaleVoice(selected)
            ? (isMaleRole ? 0.95 : 1.0)
            : (isMaleRole ? 0.82 : min(1.25, max(0.92, kind.pitch)))
        utterance.rate = kind.rate
        synthesizer.speak(utterance)
    }

    private func play(url: URL, rate: Float = 1.0) {
        do {
            // 真机上首次播放必须先激活音频会话，否则 AVAudioPlayer 静默无声
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            // 试听与正式播放用同一套归一化语速，避免「试听正常、聊天里变慢/变快」
            if abs(rate - 1.0) > 0.01 {
                player.enableRate = true
                player.rate = max(0.5, min(2.0, rate))
            }
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else {
                // 播放启动失败（如缓存文件损坏）：兜底系统语音，不再无声结束
                speakWithSystemFallback(sampleText, kind: VoiceKind(rawValue: tag ?? "") ?? .softGirl)
                return
            }
            self.player = player
            lastError = nil
        } catch {
            // 音频文件损坏/无法解码 → 系统语音兜底
            speakWithSystemFallback(sampleText, kind: VoiceKind(rawValue: tag ?? "") ?? .softGirl)
        }
    }

    /// 本次试听的文本（音频播放失败时系统语音兜底念这段）
    private var sampleText = "你好，我是你的角色，这种声音你觉得如何？"

    func stop() {
        task?.cancel()
        task = nil
        player?.stop()
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isPlaying = false
    }
}

extension PreviewPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
            self?.player = nil
        }
    }
}
