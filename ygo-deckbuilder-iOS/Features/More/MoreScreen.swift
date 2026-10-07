import SwiftUI

/// Onglet « Autre » : les écrans qu'on ouvre de temps en temps (règles, wishlist, duel,
/// catalogue), empilés dans une seule pile de navigation. Les écrans concernés savent se
/// passer de leur propre `NavigationStack` (`embedded: true`).
struct MoreScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.morePath) {
            List {
                Section {
                    row(.rules, title: t("layout.nav.rules"), systemImage: "book.closed",
                        subtitle: t("ios.more.rules"))
                    row(.wishlist, title: t("layout.nav.wishlist"), systemImage: "heart",
                        subtitle: t("ios.more.wishlist"))
                }
                Section {
                    row(.duel, title: t("layout.nav.duel"), systemImage: "bolt.shield",
                        subtitle: t("ios.more.duel"))
                    row(.catalog, title: t("layout.nav.catalog"), systemImage: "magnifyingglass",
                        subtitle: t("ios.more.catalog"))
                }
            }
            .navigationTitle(t("ios.nav.more"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
            }
            .navigationDestination(for: MoreRoute.self) { route in
                switch route {
                case .rules: RulesView(embedded: true)
                case .wishlist: WishlistScreen(embedded: true)
                case .duel: DuelScreen(embedded: true)
                case .catalog: CatalogScreen(embedded: true)
                }
            }
        }
    }

    private func row(_ route: MoreRoute, title: String, systemImage: String, subtitle: String) -> some View {
        NavigationLink(value: route) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 2)
        }
    }
}
