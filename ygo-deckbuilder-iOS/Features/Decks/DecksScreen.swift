import SwiftUI

struct DeckRoute: Hashable { let id: String }

/// Onglet Decks : liste, création (vide ou .ydk), duplication, suppression.
struct DecksScreen: View {
    @Environment(AppState.self) private var app
    @State private var decks: Loadable<[DeckListItem]> = .idle
    @State private var path: [DeckRoute] = []
    @State private var creating = false
    /// Deck tout juste créé, à ouvrir dès que la feuille de création est refermée.
    @State private var created: String?
    @State private var toDelete: DeckListItem?
    @State private var error: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                LoadableView(state: decks, retry: load) { decks in
                    if decks.isEmpty {
                        ContentUnavailableView {
                            Label(t("decks.view.empty.title"), systemImage: "rectangle.stack.badge.plus")
                        } description: {
                            Text(t("decks.view.empty.description"))
                        } actions: {
                            Button(t("decks.view.newDeck")) { creating = true }
                                .buttonStyle(.glassProminent)
                            Button(t("layout.nav.suggestions")) { app.show(.suggestions) }
                                .buttonStyle(.glass)
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(decks) { deck in
                            NavigationLink(value: DeckRoute(id: deck.id)) { DeckRow(deck: deck) }
                                .swipeActions {
                                    Button(t("decks.view.delete"), systemImage: "trash", role: .destructive) {
                                        toDelete = deck
                                    }
                                    Button(t("decks.view.duplicate"), systemImage: "plus.square.on.square") {
                                        Task { await duplicate(deck) }
                                    }
                                    .tint(.accentColor)
                                }
                                .contextMenu {
                                    Button(t("decks.view.duplicate"), systemImage: "plus.square.on.square") {
                                        Task { await duplicate(deck) }
                                    }
                                    Button(t("decks.view.delete"), systemImage: "trash", role: .destructive) {
                                        toDelete = deck
                                    }
                                }
                        }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(Theme.danger).font(.footnote)
                }
            }
            .listRowSpacing(Spacing.xxs)
            .navigationTitle(t("decks.view.title"))
            .navigationDestination(for: DeckRoute.self) { DeckBuilderScreen(deckId: $0.id) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("decks.view.newDeck"), systemImage: "plus") { creating = true }
                }
            }
            .refreshable { await load() }
            .sheet(isPresented: $creating, onDismiss: openCreated) {
                NewDeckView { created = $0.id }
            }
            .confirmationDialog(
                t("decks.view.confirmDelete", ["name": toDelete?.name ?? ""]),
                isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                titleVisibility: .visible,
                presenting: toDelete
            ) { deck in
                Button(t("decks.view.delete"), role: .destructive) {
                    Task { await delete(deck) }
                }
            }
        }
        .task(id: app.decksVersion) { await load() }
        .task(id: app.pendingDeckId) { openPending() }
        .onChange(of: app.rootTaps) {
            if app.selectedTab == .decks { path = [] }
        }
    }

    private func load() async {
        decks = await .fetch(decks) { try await app.api.decks() }
    }

    /// Deck créé ici : on l'ouvre une fois la feuille refermée. Poussée depuis la même
    /// transaction que la fermeture, la destination est avalée par SwiftUI.
    private func openCreated() {
        guard let id = created else { return }
        created = nil
        app.decksChanged()
        path = [DeckRoute(id: id)]
    }

    /// Deck à ouvrir demandé par un autre onglet (suggestion générée, deck d'un produit).
    /// Dans une tâche et non un `onChange(initial:)` : on y touche à l'état global en dehors
    /// du cycle de rendu. Surtout, aucune suspension avant la poussée : remettre
    /// `pendingDeckId` à nil annule cette tâche, puisque c'est son identité, et tout ce qui
    /// suivrait un `await` serait perdu.
    private func openPending() {
        guard let id = app.pendingDeckId else { return }
        app.pendingDeckId = nil
        path = [DeckRoute(id: id)]
    }

    private func duplicate(_ deck: DeckListItem) async {
        do {
            _ = try await app.api.duplicateDeck(deck.id)
            app.decksChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ deck: DeckListItem) async {
        do {
            try await app.api.deleteDeck(deck.id)
            app.decksChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct DeckRow: View {
    let deck: DeckListItem

    var body: some View {
        HStack(spacing: Spacing.m) {
            RemoteImage([deck.coverURL], width: .thumb) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(.fill.tertiary)
                    .overlay(Image(systemName: "rectangle.stack").foregroundStyle(.tertiary))
            }
            .aspectRatio(Theme.cardAspect, contentMode: .fit)
            .frame(width: 48)
            .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(deck.name).font(.headline).lineLimit(2)
                HStack(spacing: Spacing.xs) {
                    Pill(text: t("decks.formats.\(deck.format.rawValue)"))
                    Text([
                        t("decks.view.counts.main", ["count": deck.mainCount]),
                        t("decks.view.counts.extra", ["count": deck.extraCount]),
                        deck.sideCount > 0 ? t("decks.view.counts.side", ["count": deck.sideCount]) : nil,
                    ].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(deck.mainCount >= 40 ? Color.secondary : Theme.warning)
                }
                Text(t("decks.view.updatedOn", ["date": L10n.shared.date(deck.updatedAt)]))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}
