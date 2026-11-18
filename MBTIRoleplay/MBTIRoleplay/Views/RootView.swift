import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                DiscoverView()
            }
            .tabItem { Label("发现", systemImage: "sparkles") }
            .tag(0)

            NavigationStack {
                SessionsView()
            }
            .tabItem { Label("消息", systemImage: "bubble.left.and.bubble.right") }
            .tag(1)
            .badge(store.unreadTotal)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("我的", systemImage: "person") }
            .tag(2)
        }
        .tint(Theme.accent)
    }
}
