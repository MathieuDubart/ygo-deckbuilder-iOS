import SwiftUI

/// Ajout de cartes au deck : recherche (tes cartes par défaut) ou suggestions liées au deck.
/// Toucher une carte ouvre sa fiche (bloc « Dans ce deck ») ; le bouton + l'ajoute directement.
struct CardPickerView: View {
    let model: DeckBuilderModel

    enum Tab: Hashable { case search, suggestions }

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .search
    @State private var search: CardSearchModel?
    @State private var suggestions: Loadable<[CardSuggestion]> = .idle
    @State private var selected: CardLink?
    @State private var feedback: String?
    @State private var added = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text(t("deckBuilder.picker.search")).tag(Tab.search)
                    Text(suggestions.value.map { t("deckBuilder.picker.suggestionsCount", ["count": $0.count]) }
                         ?? t("deckBuilder.picker.suggestions")).tag(Tab.suggestions)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.s)

                switch tab {
                case .search:
                    if let search { SearchPane(search: search, onOpen: open, onAdd: add) }
                case .suggestions:
                    suggestionsPane
                }
            }
            .navigationTitle(t("ios.deck.addCards"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.actions.close"), systemImage: "checkmark") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let feedback {
                    Text(feedback)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.s + 2)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, Spacing.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: added) {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { self.feedback = nil }
                        }
                }
            }
            .animation(.snappy, value: feedback)
        }
        .task {
            if search == nil {
                var query = CardSearchQuery()
                query.owned = true
                let created = CardSearchModel(api: app.api, query: query)
                search = created
                await created.reload()
            }
        }
        .task(id: tab) {
            if tab == .suggestions {
                suggestions = await .fetch(suggestions) { try await app.api.deckCardSuggestions(model.deckId) }
            }
        }
        .cardDetailSheet($selected, builder: model)
        .sensoryFeedback(.selection, trigger: added)
    }

    private func open(_ card: CardSummary) { selected = CardLink(cardId: card.id) }

    private func add(_ card: CardSummary) {
        if let reason = model.add(card) {
            feedback = reason
        } else {
            feedback = "+1 \(card.name)"
        }
        added += 1
    }

    @ViewBuilder
    private var suggestionsPane: some View {
        ScrollView {
            LoadableView(state: suggestions) { items in
                if items.isEmpty {
                    ContentUnavailableView(t("deckBuilder.picker.suggestions"), systemImage: "sparkles",
                                           description: Text(t("deckBuilder.picker.suggestionsEmpty")))
                } else {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        Text(t("deckBuilder.picker.suggestionsHint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        CardGrid(items: items.map(\.card), minWidth: 90) { card in
                            PickerTile(card: card, inDeck: model.totalCopies(of: card.id), onOpen: { open(card) }, onAdd: { add(card) })
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.xl)
                }
            }
        }
    }
}

private struct SearchPane: View {
    @Bindable var search: CardSearchModel
    let onOpen: (CardSummary) -> Void
    let onAdd: (CardSummary) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardFiltersBar(query: $search.query)
                if search.items.isEmpty && !search.loading {
                    Text(t(search.query.owned ? "deckBuilder.picker.noOwnedResults" : "deckBuilder.picker.noResults"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, Spacing.xl)
                }
                CardGrid(items: search.items, minWidth: 90) { card in
                    PickerTile(card: card, inDeck: 0, onOpen: { onOpen(card) }, onAdd: { onAdd(card) })
                        .onAppear {
                            if card.id == search.items.last?.id { Task { await search.loadMore() } }
                        }
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .searchable(text: $search.query.q, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: t("catalog.filters.searchPlaceholderCompact"))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }
}

private struct PickerTile: View {
    let card: CardSummary
    let inDeck: Int
    let onOpen: () -> Void
    let onAdd: () -> Void

    var body: some View {
        Button(action: onOpen) {
            CardTile(card: card, quantity: card.owned, dimmed: card.owned == 0)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            Button(t("common.actions.add"), systemImage: "plus", action: onAdd)
                .labelStyle(.iconOnly)
                .font(.caption.bold())
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .padding(4)
        }
    }
}
