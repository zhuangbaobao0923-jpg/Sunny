import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    /// 账号操作确认：一个弹窗切换文案，避免叠多个 .alert 只有最后一个生效
    @State private var pendingAction: AccountAction?

    private enum AccountAction: String, Identifiable {
        case logout, delete
        var id: String { rawValue }
    }

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
                        row("它记得你什么") { router.push(.memory) }
                        divider
                        row("世界书（角色设定）") { router.push(.lore) }
                        divider
                        row("隐私设置") { store.showToast("隐私设置开发中") }
                        divider
                        row("用户协议") { store.showToast("用户协议开发中") }
                    }

                    VStack(spacing: 12) {
                        Button("退出登录") { pendingAction = .logout }
                            .buttonStyle(DarkButtonStyle())

                        Button("注销账号") { pendingAction = .delete }
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
        // 自测用：-DemoLogoutAlert 启动时直接弹一次确认框（真机上不会触发）
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-DemoLogoutAlert") {
                pendingAction = .logout
            }
        }
        .alert(alertTitle, isPresented: Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        )) {
            Button("取消", role: .cancel) { pendingAction = nil }
            if pendingAction == .delete {
                Button("确认注销", role: .destructive) {
                    pendingAction = nil
                    Task { await deleteAccount() }
                }
            } else if pendingAction == .logout {
                Button("退出登录", role: .destructive) {
                    pendingAction = nil
                    signOut()
                }
            }
        } message: {
            Text(alertMessage)
        }
    }

    private var alertTitle: String {
        pendingAction == .delete ? "注销账号？" : "退出登录？"
    }

    private var alertMessage: String {
        pendingAction == .delete
            ? "会删除你发布的所有角色并退出登录，这个操作不可恢复。"
            : "退出后需要重新登录才能聊天、发布。本机已有的聊天记录不会删除。"
    }

    private func signOut() {
        CloudSession.shared.signOut()
        store.saveProfile({ var p = store.profile; p.isLoggedIn = false; return p }())
        store.showToast("已退出登录")
    }

    /// 注销：先删云端发布内容，再退出；最后给一个明确回执
    private func deleteAccount() async {
        try? await CloudAgents.deleteMine()
        CloudSession.shared.signOut()
        store.saveProfile({ var p = store.profile; p.isLoggedIn = false; return p }())
        store.showToast("账号已注销，发布的内容已删除")
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

    // 头像 / 性别 / 城市
    @State private var avatarStore = AvatarStore.shared
    @State private var avatarItem: PhotosPickerItem?
    @State private var dialog: PickerDialog?
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var showCity = false

    private enum PickerDialog: String, Identifiable {
        case avatar, gender
        var id: String { rawValue }
    }

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
                        Group {
                            if let image = avatarStore.image {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Image("mine_avatar")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Palette.gold.opacity(0.55), lineWidth: 1))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink3)
                    } action: {
                        dialog = .avatar
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
                        dialog = .gender
                    }
                    divider
                    row {
                        Text("城市")
                            .font(Typo.body(15))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(store.profile.city.isEmpty ? "请选择" : store.profile.city)
                            .font(Typo.body(14))
                            .foregroundStyle(Palette.ink)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink3)
                    } action: {
                        showCity = true
                    }
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
        .confirmationDialog(dialog == .gender ? "设置性别" : "更换头像",
                            isPresented: Binding(
                                get: { dialog != nil },
                                set: { if !$0 { dialog = nil } }
                            ),
                            titleVisibility: .visible) {
            if dialog == .gender {
                Button("男") { saveGender("男") }
                Button("女") { saveGender("女") }
            } else {
                Button("拍摄") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        showPhotos = true
                    }
                }
                Button("从相册选择") { showPhotos = true }
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $avatarItem, matching: .images)
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    avatarStore.save(image)
                }
                avatarItem = nil
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                avatarStore.save(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCity) {
            CityPickerView(current: store.profile.city) { city in
                var profile = store.profile
                profile.city = city
                store.saveProfile(profile)
            }
        }
        .alert(editing?.rawValue ?? "", isPresented: Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } }
        )) {
            TextField("", text: $draftText)
            Button("取消", role: .cancel) { editing = nil }
            Button("保存") { commit() }
        }
    }

    private func saveGender(_ gender: String) {
        var profile = store.profile
        profile.gender = gender
        store.saveProfile(profile)
        dialog = nil
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
