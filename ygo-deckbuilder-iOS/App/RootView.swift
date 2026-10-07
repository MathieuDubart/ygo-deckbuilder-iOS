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
                        .task(id: TagLoad(tags: app.tagsVersion, collection: app.collectionVersion)) {
                            await app.loadTags()
                        }
                }
            }
        }
        .animation(.default, value: app.session)
        .animation(.default, value: app.server.url)
    }
}

/// Le référentiel d'étiquettes se recharge quand elles changent, mais aussi avec la
/// collection : un échec au lancement (hors ligne) ne doit pas condamner toute la session.
private struct TagLoad: Equatable {
    let tags: Int
    let collection: Int
}

struct MainTabView: View {
    @Environment(AppState.self) private var app

    /// Passe par `selectTab` pour que retaper l'onglet actif soit détecté : SwiftUI appelle
    /// le `set` même quand la valeur ne change pas.
    private var selection: Binding<AppTab> {
        Binding(get: { app.selectedTab }, set: { app.selectTab($0) })
    }

    var body: some View {
        TabView(selection: selection) {
            Tab(t("layout.nav.collection"), systemImage: "square.stack.3d.up.fill", value: AppTab.collection) {
                CollectionScreen()
            }
            Tab(t("layout.nav.decks"), systemImage: "rectangle.portrait.on.rectangle.portrait.angled.fill", value: AppTab.decks) {
                DecksScreen()
            }
            Tab(t("layout.nav.suggestions"), systemImage: "wand.and.sparkles", value: AppTab.suggestions) {
                SuggestionsScreen()
            }
            Tab(t("ios.nav.more"), systemImage: "ellipsis.circle.fill", value: AppTab.more) {
                MoreScreen()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
