import SwiftUI

@main
struct YGODeckBuilderApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(\.locale, L10n.shared.locale)
        }
    }
}
