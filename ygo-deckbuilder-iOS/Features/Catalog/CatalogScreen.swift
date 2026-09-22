import SwiftUI

/// Onglet recherche : tout le catalogue, filtres, et scan d'une carte par son code imprimé.
struct CatalogScreen: View {
    @Environment(AppState.self) private var app
    @State private var model: CardSearchModel?
    @State private var selected: CardLink?
    @State private var scanning = false
    @State private var pendingLink: CardLink?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    CatalogResults(model: model, selected: $selected)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(t("catalog.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("ios.scan.title"), systemImage: "camera.viewfinder") { scanning = true }
                }
            }
        }
        .task(id: app.collectionVersion) {
            if model == nil { model = CardSearchModel(api: app.api) }
            await model?.reload()
        }
        .cardDetailSheet($selected)
        .fullScreenCover(isPresented: $scanning, onDismiss: openPending) {
            CardScannerView { code, cardId in
                pendingLink = CardLink(cardId: cardId, printHint: code)
                scanning = false
            }
        }
    }

    /// La fiche s'ouvre une fois le scanner fermé (une seule présentation à la fois).
    private func openPending() {
        if let link = pendingLink {
            pendingLink = nil
            selected = link
        }
    }
}

private struct CatalogResults: View {
    @Bindable var model: CardSearchModel
    @Binding var selected: CardLink?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CardFiltersBar(query: $model.query)

                HStack {
                    Text(t("catalog.count", ["count": model.total]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if model.loading { ProgressView().controlSize(.small) }
                }

                if model.approximate {
                    Label(t("catalog.approximate", ["query": model.query.q]), systemImage: "wand.and.stars")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }

                if let error = model.error, model.items.isEmpty {
                    ContentUnavailableView(t("common.status.error"), systemImage: "wifi.exclamationmark", description: Text(error))
                } else if model.items.isEmpty && !model.loading {
                    ContentUnavailableView(
                        t("catalog.empty.title"), systemImage: "rectangle.on.rectangle.slash",
                        description: Text(t("catalog.empty.description")))
                } else {
                    CardGrid(items: model.items) { card in
                        Button { selected = CardLink(cardId: card.id) } label: {
                            CardTile(card: card, quantity: card.owned)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if card.id == model.items.last?.id { Task { await model.loadMore() } }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .searchable(text: $model.query.q, prompt: t("catalog.filters.searchPlaceholder"))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .refreshable { await model.reload() }
    }
}

/// Catégorie, archétype, tri, « possédées ».
struct CardFiltersBar: View {
    @Binding var query: CardSearchQuery
    var showsOwnedToggle = true
    @Environment(AppState.self) private var app
    @State private var archetypes: [String] = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if showsOwnedToggle {
                    FilterChip(t("catalog.filters.owned"), systemImage: "checkmark.circle", isOn: query.owned) {
                        query.owned.toggle()
                    }
                }
                ForEach([CardCategory.monster, .spell, .trap], id: \.self) { category in
                    FilterChip(t("common.categories.\(category.rawValue)"), isOn: query.category == category) {
                        query.category = query.category == category ? nil : category
                    }
                }
                Menu {
                    Picker(t("catalog.filters.archetype"), selection: $query.archetype) {
                        Text(t("catalog.filters.allArchetypes")).tag(String?.none)
                        ForEach(archetypes, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: {
                    MenuChip(title: query.archetype ?? t("catalog.filters.archetype"), systemImage: "tag", isOn: query.archetype != nil)
                }
                Menu {
                    Picker(t("catalog.filters.sortLabel"), selection: $query.sort) {
                        ForEach(CardSort.allCases) { sort in
                            Text(t("catalog.filters.sort.\(sort.rawValue)")).tag(CardSort?.some(sort))
                        }
                    }
                } label: {
                    let current = query.sort ?? (query.q.isEmpty ? .name : .relevance)
                    MenuChip(
                        title: t("catalog.filters.sortOption", ["label": t("catalog.filters.sort.\(current.rawValue)")]),
                        systemImage: "arrow.up.arrow.down", isOn: query.sort != nil)
                }
            }
            .padding(.vertical, 2)
        }
        .task {
            if archetypes.isEmpty { archetypes = (try? await app.api.archetypes()) ?? [] }
        }
    }
}

/// Libellé d'un menu déroulant présenté comme une puce de filtre.
private struct MenuChip: View {
    let title: String
    let systemImage: String
    let isOn: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(isOn ? .regular.tint(.accentColor.opacity(0.25)).interactive() : .regular.interactive(), in: .capsule)
    }
}
