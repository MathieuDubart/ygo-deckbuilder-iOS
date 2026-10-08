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
                    row(.profile, title: t("layout.nav.profile"), systemImage: "person.crop.circle",
                        subtitle: t("ios.more.profile"))
                    row(.friends, title: t("layout.nav.friends"), systemImage: "person.2",
                        subtitle: t("ios.more.friends"), badge: app.pendingRequests)
                }
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
                case .friends: FriendsScreen(embedded: true)
                case .profile: ProfileScreen(embedded: true)
                }
            }
            .navigationDestination(for: ProfileRoute.self) { route in
                ProfileScreen(username: route.username, embedded: true)
            }
        }
        .onChange(of: app.rootTaps) {
            if app.selectedTab == .more { app.morePath = NavigationPath() }
        }
    }

    private func row(
        _ route: MoreRoute, title: String, systemImage: String, subtitle: String, badge: Int = 0
    ) -> some View {
        NavigationLink(value: route) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text(title)
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(Theme.accentInk)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor, in: .capsule)
                        }
                    }
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
