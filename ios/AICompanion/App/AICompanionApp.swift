import SwiftUI

@main
struct AICompanionApp: App {
    @State private var store = AppStore()
    @State private var router = AppRouter()
    @State private var cloud = CloudSession.shared
    @State private var gate = AuthGate.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .environment(router)
                .task {
                    // 登录后拉一次云端公开的角色，进首页推荐
                    await store.refreshCloudAgents()
                    #if DEBUG
                    await BreezeSelfTest.runIfRequested()
                    #endif
                }
                // 未登录时点任何需要账号的功能 → 弹登录页（可以关掉继续逛）
                .sheet(isPresented: Binding(
                    get: { gate.needsLogin },
                    set: { gate.needsLogin = $0 }
                )) {
                    LoginView(isSheet: true)
                }
                .onChange(of: cloud.isLoggedIn) { _, loggedIn in
                    if loggedIn {
                        gate.needsLogin = false
                        Task { await store.refreshCloudAgents() }
                    }
                }
                .preferredColorScheme(.dark)
                .tint(Palette.gold)
        }
    }
}
