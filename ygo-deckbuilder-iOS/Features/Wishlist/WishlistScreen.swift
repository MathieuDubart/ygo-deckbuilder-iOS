import SwiftUI

/// Cartes à trouver : impression visée, budget, priorité, deck qui en a besoin.
/// « Je l'ai » la déplace dans la collection.
struct WishlistScreen: View {
    @Environment(AppState.self) private var app
    @State private var wishlist: Loadable<Wishlist> = .idle
    @State private var selected: CardLink?
    @State private var busy: Set<String> = []
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                LoadableView(state: wishlist, retry: load) { list in
                    Section {
                        HStack(spacing: 8) {
                            StatTile(label: t("wishlist.view.stats.cards"), value: L10n.shared.number(list.items.reduce(0) { $0 + $1.quantity }))
                            StatTile(label: t("wishlist.view.stats.estimatedCost"), value: L10n.shared.price(list.totalEstimated), tint: .accentColor)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    if list.items.isEmpty {
                        ContentUnavailableView(t("wishlist.view.empty.title"), systemImage: "heart",
                                               description: Text(t("wishlist.view.empty.description")))
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(WishlistPriority.allCases.reversed()) { priority in
                            let items = list.items.filter { $0.priority == priority }
                            if !items.isEmpty {
                                Section(t("wishlist.priorities.\(priority.rawValue)")) {
                                    ForEach(items) { item in row(item) }
                                }
                            }
                        }
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(t("wishlist.view.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
            }
            .refreshable { await load() }
        }
        .task(id: app.wishlistVersion) { await load() }
        .cardDetailSheet($selected)
        .sensoryFeedback(.success, trigger: message)
    }

    private func load() async {
        wishlist = await .fetch(wishlist) { try await app.api.wishlist() }
    }

    private func row(_ item: WishlistItem) -> some View {
        CardRow(card: item.card, subtitle: subtitle(item)) {
            VStack(alignment: .trailing, spacing: 2) {
                Text("×\(item.quantity)").font(.subheadline.bold().monospacedDigit())
                Text(L10n.shared.price(item.unitPrice)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .onTapGesture { selected = CardLink(cardId: item.card.id) }
        .disabled(busy.contains(item.id))
        .swipeActions(edge: .leading) {
            Button(t("wishlist.row.acquired"), systemImage: "checkmark") {
                Task { await acquired(item) }
            }
            .tint(Theme.success)
        }
        .swipeActions(edge: .trailing) {
            Button(t("wishlist.row.remove"), systemImage: "trash", role: .destructive) {
                Task { await remove(item) }
            }
        }
        .contextMenu {
            Button(t("wishlist.row.acquired"), systemImage: "checkmark") { Task { await acquired(item) } }
            Menu(t("wishlist.row.priority")) {
                ForEach(WishlistPriority.allCases) { priority in
                    Button(t("wishlist.priorities.\(priority.rawValue)")) {
                        Task { await setPriority(item, priority) }
                    }
                }
            }
            Button(t("wishlist.row.remove"), systemImage: "trash", role: .destructive) { Task { await remove(item) } }
        }
    }

    private func subtitle(_ item: WishlistItem) -> String {
        var parts: [String] = []
        if let print = item.print { parts.append("\(print.printCode) · \(print.rarity)") }
        if let language = item.language { parts.append(language) }
        if let max = item.maxPrice { parts.append(t("wishlist.row.budget", ["price": L10n.shared.price(max)])) }
        if let deck = item.deck { parts.append(deck.name) }
        return parts.isEmpty ? item.card.type : parts.joined(separator: " · ")
    }

    @discardableResult
    private func perform(_ item: WishlistItem, _ work: () async throws -> Void) async -> Bool {
        busy.insert(item.id)
        defer { busy.remove(item.id) }
        do {
            try await work()
            app.wishlistChanged()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func acquired(_ item: WishlistItem) async {
        guard await perform(item, { try await app.api.markAcquired(item.id) }) else { return }
        message = t("wishlist.row.acquiredToast")
        app.collectionChanged()
    }

    private func remove(_ item: WishlistItem) async {
        await perform(item) { try await app.api.removeFromWishlist(item.id) }
    }

    private func setPriority(_ item: WishlistItem, _ priority: WishlistPriority) async {
        await perform(item) { try await app.api.updateWishlist(item.id, UpdateWishlistBody(priority: priority)) }
    }
}
