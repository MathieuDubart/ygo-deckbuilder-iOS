import SwiftUI

/// Aiguillage : choix du serveur → connexion → application.
struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            if app.server.url == nil {
                ServerSetupView()
            } else {
                switch app.session {
                case .checking:
                    ProgressView()
                        .task { await app.restore() }
                case .signedOut:
                    AuthView()
                case .signedIn:
                    MainTabView()
                }
            }
        }
        .animation(.default, value: app.session)
        .animation(.default, value: app.server.url)
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            Tab(t("layout.nav.collection"), systemImage: "square.stack.3d.up.fill", value: AppTab.collection) {
                CollectionScreen()
            }
            Tab(t("layout.nav.decks"), systemImage: "rectangle.portrait.on.rectangle.portrait.angled.fill", value: AppTab.decks) {
                DecksScreen()
            }
            Tab(t("layout.nav.suggestions"), systemImage: "wand.and.sparkles", value: AppTab.suggestions) {
                SuggestionsScreen()
            }
            Tab(t("layout.nav.wishlist"), systemImage: "heart.fill", value: AppTab.wishlist) {
                WishlistScreen()
            }
            Tab(t("layout.nav.duel"), systemImage: "bolt.shield.fill", value: AppTab.duel) {
                DuelScreen()
            }
            Tab(t("layout.nav.catalog"), systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                CatalogScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
