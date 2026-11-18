import SwiftUI

@main
struct AICompanionApp: App {
    @State private var store = AppStore()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .environment(router)
                .preferredColorScheme(.dark)
                .tint(Palette.gold)
        }
    }
}
