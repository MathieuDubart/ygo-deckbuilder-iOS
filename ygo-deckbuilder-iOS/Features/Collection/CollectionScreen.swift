import SwiftUI

/// Onglet Collection : chiffres clés, cartes (par impression, état, langue) et produits.
struct CollectionScreen: View {
    enum Tab: Hashable { case cards, products, releases }

    @Environment(AppState.self) private var app
    @State private var tab: Tab = .cards
    @State private var stats: Loadable<CollectionStats> = .idle
    @State private var selected: CardLink?
    @State private var importing = false
    @State private var choosingLanguage = false
    @State private var scanning = false
    @State private var path = NavigationPath()
    /// Incrémenté par les listes quand on tire pour rafraîchir : le résumé doit suivre le
    /// geste, sans quoi il afficherait d'anciens chiffres juste au-dessus d'une liste à jour.
    @State private var refreshToken = 0
    /// Partagé entre la liste des extensions et leurs fiches : les deux doivent compter pareil.
    @State private var anyEdition = false
    /// Résultat du dernier import, consommé à la fermeture de la feuille par `openImported`.
    @State private var imported: ImportSetResult?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch tab {
                case .cards:
                    CollectionCardsList(header: header, selected: $selected, refreshToken: $refreshToken)
                case .products:
                    ProductsList(header: header, refreshToken: $refreshToken, onAdd: { importing = true })
                case .releases:
                    ReleasesList(header: header, anyEdition: $anyEdition, refreshToken: $refreshToken)
                }
            }
            .navigationTitle(t("collection.view.title"))
            .navigationDestination(for: ProductRoute.self) { ProductDetailView(productId: $0.id) }
            .navigationDestination(for: ReleaseRoute.self) {
                ReleaseDetailView(setId: $0.setId, anyEdition: $anyEdition)
            }
            // Le profil d'un ami s'ouvre depuis le bloc de comparaison d'une extension
            .navigationDestination(for: ProfileRoute.self) {
                ProfileScreen(username: $0.username, embedded: true)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("ios.scan.title"), systemImage: "camera.viewfinder") { scanning = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu(t("common.actions.add"), systemImage: "plus") {
                        Button(t("collection.view.addCards"), systemImage: "magnifyingglass") {
                            app.openMore(.catalog)
                        }
                        Button(t("collection.view.addProduct"), systemImage: "shippingbox") { importing = true }
                        Button(t("ios.scan.title"), systemImage: "camera.viewfinder") { scanning = true }
                        Divider()
                        Button(t("collection.language.title"), systemImage: "character.book.closed") {
                            choosingLanguage = true
                        }
                    }
                }
            }
        }
        .task(id: StatsKey(version: app.collectionVersion, refresh: refreshToken)) {
            stats = await .fetch(stats) { try await app.api.collectionStats() }
        }
        .cardDetailSheet($selected)
        .sheet(isPresented: $importing, onDismiss: openImported) {
            ImportProductView { imported = $0 }
        }
        .sheet(isPresented: $choosingLanguage) { CollectionLanguageView() }
        .fullScreenCover(isPresented: $scanning) {
            CardScannerView()
        }
        .onChange(of: app.rootTaps) {
            if app.selectedTab == .collection { path = NavigationPath() }
        }
    }

    /// Où atterrir après un import, une fois la feuille refermée. Un deck monté est la seule
    /// preuve visible que la case « ajouter aussi son deck » a servi : on l'ouvre, comme le
    /// fait déjà « créer le deck » sur la fiche produit. Plusieurs listes (coffret à deux
    /// decks) : aucune n'est « la » bonne, on reste donc sur le produit, qui les porte toutes.
    private func openImported() {
        guard let result = imported else { return }
        imported = nil
        if result.decks.count == 1, let deck = result.decks.first {
            app.openDeck(deck.id)
        } else {
            tab = .products
            path.append(ProductRoute(id: result.productId))
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.l) {
            HStack(spacing: Spacing.s) {
                StatTile(label: t("collection.view.stats.copies"), value: stats.value.map { L10n.shared.number($0.totalCopies) } ?? "—")
                StatTile(label: t("collection.view.stats.distinctCards"), value: stats.value.map { L10n.shared.number($0.distinctCards) } ?? "—")
                StatTile(label: t("collection.view.stats.estimatedValue"), value: L10n.shared.price(stats.value?.estimatedValue), tint: .accentColor)
            }
            Picker(t("collection.view.tabs.label"), selection: $tab) {
                Text(t("collection.view.tabs.cards")).tag(Tab.cards)
                Text(t("collection.view.tabs.products")).tag(Tab.products)
                Text(t("collection.view.tabs.releases")).tag(Tab.releases)
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct StatsKey: Equatable {
    let version: Int
    let refresh: Int
}

struct ProductRoute: Hashable { let id: String }

// MARK: - Cartes

private struct CollectionCardsList<Header: View>: View {
    let header: Header
    @Binding var selected: CardLink?
    @Binding var refreshToken: Int

    @Environment(AppState.self) private var app
    @State private var query = CollectionQuery()
    @State private var items: [CollectionItem] = []
    @State private var totalPages = 1
    @State private var facets: CollectionFacets?
    /// Hors de `query` : la pagination ne doit pas relancer le chargement des filtres.
    @State private var page = 1
    @State private var wantsMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var busy: Set<String> = []
    /// Dernier texte de recherche vu par la tâche de chargement.
    @State private var typed = ""

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: Spacing.s, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                filters
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.l, bottom: 0, trailing: Spacing.l))
                    .listRowBackground(Color.clear)
            }

            if let error, items.isEmpty {
                ContentUnavailableView(t("common.status.error"), systemImage: "wifi.exclamationmark", description: Text(error))
                    .listRowBackground(Color.clear)
            } else if items.isEmpty && !loading {
                ContentUnavailableView(
                    query.isFiltering ? t("collection.view.empty.noMatch") : t("collection.view.empty.title"),
                    systemImage: "square.stack.3d.up.slash",
                    description: Text(query.isFiltering ? "" : t("collection.view.empty.description")))
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(items) { item in
                    CollectionRow(item: item, busy: busy.contains(item.id)) { delta in
                        Task { await setQuantity(item, item.quantity + delta) }
                    }
                    .contentShape(.rect)
                    .onTapGesture { selected = CardLink(cardId: item.card.id) }
                    .contextMenu {
                        TagMenuButtons(attached: item.card.tags) { tag, on in
                            try? await app.api.tagCard(tag.id, cardId: item.card.id, on: on)
                            app.tagsChanged()
                        }
                    }
                    .swipeActions {
                        Button(t("common.actions.delete"), systemImage: "trash", role: .destructive) {
                            Task { await setQuantity(item, 0) }
                        }
                    }
                    .onAppear {
                        if item.id == items.last?.id { wantsMore = true }
                    }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Spacing.l)
        .searchable(text: $query.q, prompt: t("collection.view.filterPlaceholder"))
        .task(id: TaskKey(query: query, version: app.collectionVersion)) {
            // Le délai ne vaut que pour la frappe : une facette ou un tri partent tout de suite.
            let isTyping = query.q != typed
            typed = query.q
            if isTyping {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            await reload()
        }
        .task(id: PageRequest(key: reloadKey, wants: wantsMore, page: page)) {
            guard wantsMore else { return }
            await loadMore()
        }
        .task(id: app.collectionVersion) { facets = try? await app.api.collectionFacets() }
        // Recharger soi-même, et non via `collectionChanged` : sinon l'indicateur de
        // rafraîchissement disparaît avant que les données ne soient là.
        .refreshable {
            refreshToken += 1
            await reload()
            facets = try? await app.api.collectionFacets()
        }
    }

    /// La page ne fait pas partie de l'identité : l'y mettre relancerait un rechargement à
    /// chaque page chargée, qui remettrait la liste à la première — en boucle.
    private struct TaskKey: Equatable {
        let query: CollectionQuery
        let version: Int

        init(query: CollectionQuery, version: Int) {
            var identity = query
            identity.page = 1
            self.query = identity
            self.version = version
        }
    }

    private var reloadKey: TaskKey { TaskKey(query: query, version: app.collectionVersion) }

    /// La demande de page porte l'identité du rechargement : changer de filtre doit vraiment
    /// annuler la page en vol. Surtout, elle ne porte PAS `loading` : `loadMore` modifie
    /// `loading`, qui est lu par `body` — l'y mettre ferait changer l'identité au milieu du
    /// chargement, et la tâche s'annulerait elle-même avant d'avoir rien ramené.
    private struct PageRequest: Equatable {
        let key: TaskKey
        let wants: Bool
        let page: Int
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            FilterBar {
                FacetMenu(
                    allLabel: t("collection.filters.allCategories"),
                    options: facets?.categories ?? [],
                    selection: Binding(
                        get: { query.category?.rawValue },
                        set: { query.category = $0.flatMap(CardCategory.init(rawValue:)) })
                ) { t("common.categories.\($0.value)") }

                FacetMenu(
                    allLabel: t("collection.filters.allArchetypes"),
                    options: facets?.archetypes ?? [], selection: $query.archetype)

                FacetMenu(
                    allLabel: t("collection.filters.allRarities"),
                    options: facets?.rarities ?? [], selection: $query.rarity)

                FacetMenu(
                    allLabel: t("collection.filters.allSets"),
                    options: facets?.sets ?? [], selection: $query.setId)

                FacetMenu(
                    allLabel: t("collection.filters.allLanguages"),
                    options: facets?.languages ?? [],
                    selection: Binding(
                        get: { query.language?.rawValue },
                        set: { query.language = $0.flatMap(CardLanguage.init(rawValue:)) }))

                FacetMenu(
                    allLabel: t("collection.filters.allConditions"),
                    options: facets?.conditions ?? [],
                    selection: Binding(
                        get: { query.condition?.rawValue },
                        set: { query.condition = $0.flatMap(CardCondition.init(rawValue:)) })
                ) { t("collection.conditions.\($0.value)") }

                Menu {
                    Picker(t("collection.filters.sort"), selection: $query.sort) {
                        ForEach(CollectionSort.allCases) { sort in
                            Text(t("collection.filters.sorts.\(sort.rawValue)")).tag(sort)
                        }
                    }
                } label: {
                    ChipLabel(isOn: query.sort != .name) {
                        Label(
                            t("collection.filters.sortOption",
                              ["label": t("collection.filters.sorts.\(query.sort.rawValue)")]),
                            systemImage: "arrow.up.arrow.down")
                    }
                }

                FilterChip(
                    t("collection.filters.firstEdition"), isOn: query.firstEdition,
                    action: { query.firstEdition.toggle() })
            }

            FilterBar {
                TagFilterRow(selection: $query.tagIds) { $0.cardCount }
            }
        }
    }

    private func reload() async {
        loading = true
        // Relâcher la demande de page ici, et pas seulement en cas de succès : une demande
        // armée pendant le rechargement resterait sinon coincée, sans rien pour la relancer.
        defer {
            loading = false
            wantsMore = false
        }
        do {
            var first = query
            first.page = 1
            let result = try await app.api.collection(first)
            items = result.items
            totalPages = result.totalPages
            page = 1
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        // Ne pas consommer la demande ici : un rechargement en vol (une frappe) la ferait
        // disparaître sans charger, et la liste resterait bloquée sur sa page.
        guard page < totalPages, !loading else { return }
        defer { wantsMore = false }
        loading = true
        defer { loading = false }
        var next = query
        next.page = page + 1
        guard let result = try? await app.api.collection(next), !Task.isCancelled else { return }
        let known = Set(items.map(\.id))
        items += result.items.filter { !known.contains($0.id) }
        page = next.page
        totalPages = result.totalPages
    }

    /// 0 = ligne supprimée.
    private func setQuantity(_ item: CollectionItem, _ quantity: Int) async {
        busy.insert(item.id)
        defer { busy.remove(item.id) }
        do {
            try await app.api.setCollectionQuantity(item.id, quantity: max(0, quantity))
            app.collectionChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct CollectionRow: View {
    let item: CollectionItem
    let busy: Bool
    let change: (Int) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            CardArt(card: item.card, width: .thumb)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.card.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                FlowLayout(spacing: Spacing.xxs) {
                    if let impression = item.print {
                        Pill(text: impression.printCode)
                        Pill(
                            text: impression.rarity,
                            tint: Theme.isPremiumRarity(impression.rarity) ? Theme.gold : .secondary)
                    } else {
                        Pill(text: t("collection.row.unknownPrint"))
                    }
                    Pill(text: item.language)
                    Pill(text: t("collection.conditions.\(item.condition)"))
                    if item.firstEdition { Pill(text: "1st", tint: .accentColor) }
                    TagPills(tagIds: item.card.tags)
                }
                Text(L10n.shared.price(item.print?.price ?? item.card.priceCardmarket))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.xs)
            QuantityStepper(quantity: item.quantity, busy: busy, change: change)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

/// − quantité + dans une capsule compacte.
struct QuantityStepper: View {
    let quantity: Int
    var busy = false
    let change: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(t("collection.row.removeCopy"), systemImage: "minus") { change(-1) }
                .frame(width: 32, height: 32)
            Text("\(quantity)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(minWidth: 22)
                .contentTransition(.numericText())
            Button(t("collection.row.addCopy"), systemImage: "plus") { change(1) }
                .frame(width: 32, height: 32)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.footnote.weight(.semibold))
        .background(.fill.tertiary, in: .capsule)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
        .animation(.snappy, value: quantity)
    }
}
