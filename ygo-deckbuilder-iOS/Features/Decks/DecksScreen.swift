import SwiftUI

struct DeckRoute: Hashable { let id: String }

/// Onglet Decks : liste, création (vide ou .ydk), duplication, suppression.
struct DecksScreen: View {
    @Environment(AppState.self) private var app
    @State private var decks: Loadable<[DeckListItem]> = .idle
    @State private var path: [DeckRoute] = []
    @State private var creating = false
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
                            Button(t("layout.nav.suggestions")) { app.selectedTab = .suggestions }
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
            .sheet(isPresented: $creating) {
                NewDeckView { deck in
                    app.decksChanged()
                    path.append(DeckRoute(id: deck.id))
                }
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
        .onChange(of: app.pendingDeckId, initial: true) { _, id in
            guard let id else { return }
            app.pendingDeckId = nil
            path = [DeckRoute(id: id)]
        }
    }

    private func load() async {
        decks = await .fetch(decks) { try await app.api.decks() }
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
