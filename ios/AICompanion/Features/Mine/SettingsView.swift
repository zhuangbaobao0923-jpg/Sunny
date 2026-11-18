import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "设置", onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 16) {
                    groupCard {
                        row("账号资料") { router.push(.profile) }
                        divider
                        row("对话模型（接真实 AI）") { router.push(.model) }
                        divider
                        row("语音引擎（本地免费）") { router.push(.voice) }
                        divider
                        row("隐私设置") { store.showToast("隐私设置开发中") }
                        divider
                        row("用户协议") { store.showToast("用户协议开发中") }
                    }

                    VStack(spacing: 12) {
                        Button("退出登录") {
                            store.saveProfile({ var p = store.profile; p.isLoggedIn = false; return p }())
                            store.showToast("已退出登录")
                        }
                        .buttonStyle(DarkButtonStyle())

                        Button("注销账号") { confirmDelete = true }
                        .buttonStyle(GhostButtonStyle(tint: Palette.danger, border: Palette.line2))
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.canvas)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .alert("确认注销账号？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("确认注销", role: .destructive) {
                store.showToast("注销申请已提交")
            }
        } message: {
            Text("注销后账号数据与聊天记录将不可恢复。")
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 16)
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Typo.body(15))
                    .foregroundStyle(Palette.ink)
                Spacer()
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

    private func groupCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
            )
    }
}

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editing: EditField?
    @State private var draftText = ""

    private enum EditField: String, Identifiable {
        case nickname = "昵称"
        case signature = "个性签名"
        case city = "城市"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "账号资料", onBack: { dismiss() })

            ScrollView {
                VStack(spacing: 0) {
                    row {
                        Text("头像")
                            .font(Typo.body(15))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Image("mine_avatar")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 38, height: 38)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Palette.gold.opacity(0.55), lineWidth: 1))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink3)
                    } action: {
                        store.showToast("头像上传开发中")
                    }
                    divider
                    valueRow("昵称", store.profile.nickname, .nickname)
                    divider
                    row {
                        Text("性别")
                            .font(Typo.body(15))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(store.profile.gender)
                            .font(Typo.body(14))
                            .foregroundStyle(Palette.ink)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink3)
                    } action: {
                        var profile = store.profile
                        profile.gender = profile.gender == "男" ? "女" : "男"
                        store.saveProfile(profile)
                    }
                    divider
                    valueRow("城市", store.profile.city, .city)
                    divider
                    valueRow("个性签名", store.profile.signature, .signature)
                }
                .background(Palette.card)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(Palette.line, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.canvas)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .alert(editing?.rawValue ?? "", isPresented: Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } }
        )) {
            TextField("", text: $draftText)
            Button("取消", role: .cancel) { editing = nil }
            Button("保存") { commit() }
        }
    }

    private func commit() {
        guard let editing else { return }
        var profile = store.profile
        switch editing {
        case .nickname: profile.nickname = draftText
        case .signature: profile.signature = draftText
        case .city: profile.city = draftText
        }
        store.saveProfile(profile)
        self.editing = nil
    }

    private func valueRow(_ title: String, _ value: String, _ field: EditField) -> some View {
        row {
            Text(title)
                .font(Typo.body(15))
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(value.isEmpty ? "未填写" : value)
                .font(Typo.body(14))
                .foregroundStyle(value.isEmpty ? Palette.ink3 : Palette.ink)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink3)
        } action: {
            draftText = value
            editing = field
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 16)
    }

    private func row<Content: View>(
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) { content() }
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
