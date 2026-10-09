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
    @State private var query = DecksQuery()
    /// Dernier texte vu : sert à distinguer la frappe d'un changement de facette.
    @State private var typed = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    filters
                        .listRowInsets(EdgeInsets(top: 0, leading: Spacing.l, bottom: 0, trailing: Spacing.l))
                        .listRowBackground(Color.clear)
                }
                LoadableView(state: decks, retry: load) { decks in
                    if decks.isEmpty {
                        // Un filtre actif change le sens d'une liste vide : « rien ne
                        // correspond », pas « crée ton premier deck ».
                        if query.isFiltering {
                            ContentUnavailableView {
                                Label(t("decks.view.noResults.title"), systemImage: "line.3.horizontal.decrease")
                            } description: {
                                Text(t("decks.view.noResults.description"))
                            } actions: {
                                Button(t("decks.view.noResults.clear")) { query = DecksQuery() }
                                    .buttonStyle(.glass)
                            }
                            .listRowBackground(Color.clear)
                        } else {
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
                        }
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
                                    TagMenuButtons(attached: deck.tags) { tag, on in
                                        await tagDeck(deck, tag, on)
                                    }
                                    if !app.tags.isEmpty { Divider() }
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
            .listStyle(.insetGrouped)
            .listSectionSpacing(Spacing.l)
            .listRowSpacing(Spacing.xxs)
            .navigationTitle(t("decks.view.title"))
            .searchable(text: $query.q, prompt: t("decks.view.filterPlaceholder"))
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
        .task(id: Reload(query: query, version: app.decksVersion)) {
            // Le délai ne vaut que pour la frappe : une facette ou un tri partent tout de suite.
            let isTyping = query.q != typed
            typed = query.q
            if isTyping {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            await load()
        }
        .task(id: app.pendingDeckId) { openPending() }
        .onChange(of: app.rootTaps) {
            if app.selectedTab == .decks { path = [] }
        }
    }

    /// Identité de la tâche de chargement : les filtres et le compteur global de decks.
    private struct Reload: Equatable {
        let query: DecksQuery
        let version: Int
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            FilterBar {
                FacetMenu(
                    allLabel: t("decks.view.allFormats"),
                    options: DeckFormat.allCases.map { FacetValue(value: $0.rawValue, count: 0, label: nil) },
                    selection: Binding(
                        get: { query.format?.rawValue },
                        set: { query.format = $0.flatMap(DeckFormat.init(rawValue:)) })
                ) { t("decks.formats.\($0.value)") }

                Menu {
                    Picker(t("decks.view.sort"), selection: $query.sort) {
                        ForEach(DecksQuery.Sort.allCases) { sort in
                            Text(t("decks.view.sorts.\(sort.rawValue)")).tag(sort)
                        }
                    }
                } label: {
                    ChipLabel(isOn: query.sort != .updated) {
                        Label(
                            t("decks.view.sortOption",
                              ["label": t("decks.view.sorts.\(query.sort.rawValue)")]),
                            systemImage: "arrow.up.arrow.down")
                    }
                }
            }

            FilterBar {
                TagFilterRow(selection: $query.tagIds) { $0.decks }
            }
        }
    }

    private func load() async {
        decks = await .fetch(decks) { try await app.api.decks(query) }
    }

    private func tagDeck(_ deck: DeckListItem, _ tag: Tag, _ on: Bool) async {
        do {
            try await app.api.tagDeck(tag.id, deckId: deck.id, on: on)
            app.tagsChanged()
            app.decksChanged()
        } catch {
            self.error = error.localizedDescription
        }
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
                FlowLayout(spacing: Spacing.xxs) {
                    Pill(text: t("decks.formats.\(deck.format.rawValue)"))
                    if let style = deck.style {
                        Pill(text: t("decks.styles.\(style.rawValue)"), tint: .accentColor)
                    }
                    // Monté depuis un produit : savoir d'où vient un deck qu'on n'a pas
                    // écrit soi-même évite de le prendre pour un brouillon oublié.
                    if deck.isFromProduct {
                        Pill(text: t("decks.view.fromProduct"), tint: .accentColor)
                    }
                    TagPills(tagIds: deck.tags)
                }
                Text([
                    t("decks.view.counts.main", ["count": deck.mainCount]),
                    t("decks.view.counts.extra", ["count": deck.extraCount]),
                    deck.sideCount > 0 ? t("decks.view.counts.side", ["count": deck.sideCount]) : nil,
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.monospacedDigit())
                .foregroundStyle(deck.mainCount >= 40 ? Color.secondary : Theme.warning)
                Text(t("decks.view.updatedOn", ["date": L10n.shared.date(deck.updatedAt)]))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            // La colonne de texte prend la place : sans ça le badge colle aux noms courts
            .frame(maxWidth: .infinity, alignment: .leading)
            // Un deck trop incomplet pour être noté n'affiche rien : un zéro serait un jugement
            if let strength = deck.strength {
                ScoreBadge(score: strength).frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}
