import SwiftUI

/// Onglet Collection : chiffres clés, cartes (par impression, état, langue) et produits.
struct CollectionScreen: View {
    enum Tab: Hashable { case cards, products }

    @Environment(AppState.self) private var app
    @State private var tab: Tab = .cards
    @State private var stats: Loadable<CollectionStats> = .idle
    @State private var selected: CardLink?
    @State private var importing = false
    @State private var scanning = false
    @State private var pendingLink: CardLink?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch tab {
                case .cards: CollectionCardsList(header: header, selected: $selected)
                case .products: ProductsList(header: header, onAdd: { importing = true })
                }
            }
            .navigationTitle(t("collection.view.title"))
            .navigationDestination(for: ProductRoute.self) { ProductDetailView(productId: $0.id) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("ios.scan.title"), systemImage: "camera.viewfinder") { scanning = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu(t("common.actions.add"), systemImage: "plus") {
                        Button(t("collection.view.addCards"), systemImage: "magnifyingglass") {
                            app.selectedTab = .search
                        }
                        Button(t("collection.view.addProduct"), systemImage: "shippingbox") { importing = true }
                        Button(t("ios.scan.title"), systemImage: "camera.viewfinder") { scanning = true }
                    }
                }
            }
        }
        .task(id: app.collectionVersion) {
            stats = await .fetch(stats) { try await app.api.collectionStats() }
        }
        .cardDetailSheet($selected)
        .sheet(isPresented: $importing) {
            ImportProductView { productId in
                tab = .products
                path.append(ProductRoute(id: productId))
            }
        }
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
            }
            .pickerStyle(.segmented)
        }
    }
}

struct ProductRoute: Hashable { let id: String }

// MARK: - Cartes

private struct CollectionCardsList<Header: View>: View {
    let header: Header
    @Binding var selected: CardLink?

    @Environment(AppState.self) private var app
    @State private var filter = ""
    @State private var items: [CollectionItem] = []
    @State private var page = 1
    @State private var totalPages = 1
    @State private var loading = false
    @State private var error: String?
    @State private var busy: Set<String> = []

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: Spacing.s, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            if let error, items.isEmpty {
                ContentUnavailableView(t("common.status.error"), systemImage: "wifi.exclamationmark", description: Text(error))
                    .listRowBackground(Color.clear)
            } else if items.isEmpty && !loading {
                ContentUnavailableView(
                    filter.isEmpty ? t("collection.view.empty.title") : t("collection.view.empty.noMatch"),
                    systemImage: "square.stack.3d.up.slash",
                    description: Text(filter.isEmpty ? t("collection.view.empty.description") : ""))
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(items) { item in
                    CollectionRow(item: item, busy: busy.contains(item.id)) { delta in
                        Task { await setQuantity(item, item.quantity + delta) }
                    }
                    .contentShape(.rect)
                    .onTapGesture { selected = CardLink(cardId: item.card.id) }
                    .swipeActions {
                        Button(t("common.actions.delete"), systemImage: "trash", role: .destructive) {
                            Task { await setQuantity(item, 0) }
                        }
                    }
                    .onAppear {
                        if item.id == items.last?.id { Task { await loadMore() } }
                    }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Spacing.l)
        .searchable(text: $filter, prompt: t("collection.view.filterPlaceholder"))
        .task(id: TaskKey(filter: filter, version: app.collectionVersion)) {
            if !filter.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await reload()
        }
        .refreshable {
            await reload()
            app.collectionChanged()
        }
    }

    private struct TaskKey: Equatable {
        let filter: String
        let version: Int
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            let result = try await app.api.collection(q: filter, page: 1)
            items = result.items
            page = result.page
            totalPages = result.totalPages
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard page < totalPages, !loading else { return }
        loading = true
        defer { loading = false }
        if let result = try? await app.api.collection(q: filter, page: page + 1) {
            let known = Set(items.map(\.id))
            items += result.items.filter { !known.contains($0.id) }
            page = result.page
            totalPages = result.totalPages
        }
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
                    Pill(text: item.print.map { "\($0.printCode) · \($0.rarity)" } ?? t("collection.row.unknownPrint"))
                    Pill(text: item.language)
                    Pill(text: t("collection.conditions.\(item.condition)"))
                    if item.firstEdition { Pill(text: "1st", tint: .accentColor) }
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
