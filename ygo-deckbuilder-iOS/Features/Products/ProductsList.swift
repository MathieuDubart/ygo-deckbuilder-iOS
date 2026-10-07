import SwiftUI

/// Produits ajoutés à la collection (structure decks, tins, coffrets…).
struct ProductsList<Header: View>: View {
    let header: Header
    @Binding var refreshToken: Int
    let onAdd: () -> Void

    @Environment(AppState.self) private var app
    @State private var products: Loadable<[OwnedProduct]> = .idle
    @State private var query = OwnedProductsQuery()
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

            LoadableView(state: products, retry: load) { products in
                if products.isEmpty, query.isFiltering {
                    ContentUnavailableView(
                        t("products.tab.empty.noMatch"), systemImage: "line.3.horizontal.decrease.circle")
                        .listRowBackground(Color.clear)
                } else if products.isEmpty {
                    ContentUnavailableView {
                        Label(t("products.tab.empty.title"), systemImage: "shippingbox")
                    } description: {
                        Text(t("products.tab.empty.description"))
                    } actions: {
                        Button(t("products.tab.addProduct"), action: onAdd)
                            .buttonStyle(.glassProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(products) { product in
                        NavigationLink(value: ProductRoute(id: product.id)) {
                            OwnedProductRow(product: product)
                        }
                        .contextMenu {
                            TagMenuButtons(attached: product.tags) { tag, on in
                                try? await app.api.tagSet(tag.id, setId: product.set.id, on: on)
                                app.tagsChanged()
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Spacing.l)
        .searchable(text: $query.q, prompt: t("products.filters.searchPlaceholder"))
        .task(id: Reload(query: query, version: app.collectionVersion)) {
            // Le délai ne vaut que pour la frappe : une facette ou un tri partent tout de suite.
            let isTyping = query.q != typed
            typed = query.q
            if isTyping {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            await load()
        }
        .refreshable {
            refreshToken += 1
            await load()
        }
    }

    private struct Reload: Equatable {
        let query: OwnedProductsQuery
        let version: Int
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            FilterBar {
                FacetMenu(
                    allLabel: t("products.filters.allKinds"),
                    options: ProductKind.allCases.map { FacetValue(value: $0.rawValue, count: 0, label: nil) },
                    selection: Binding(
                        get: { query.kind?.rawValue },
                        set: { query.kind = $0.flatMap(ProductKind.init(rawValue:)) })
                ) { t("products.kinds.\($0.value)") }

                Menu {
                    Picker(t("products.filters.sort"), selection: $query.sort) {
                        ForEach(OwnedProductsQuery.Sort.allCases) { sort in
                            Text(t("products.filters.sorts.\(sort.rawValue)")).tag(sort)
                        }
                    }
                } label: {
                    ChipLabel(isOn: query.sort != .added) {
                        Label(
                            t("products.filters.sortOption",
                              ["label": t("products.filters.sorts.\(query.sort.rawValue)")]),
                            systemImage: "arrow.up.arrow.down")
                    }
                }

                FilterChip(
                    t("products.filters.complete"), isOn: query.complete,
                    action: { query.complete.toggle() })
            }

            FilterBar {
                TagFilterRow(selection: $query.tagIds) { $0.setCount }
            }
        }
    }

    private func load() async {
        products = await .fetch(products) { try await app.api.ownedProducts(query) }
    }
}

private struct OwnedProductRow: View {
    let product: OwnedProduct

    var body: some View {
        HStack(spacing: Spacing.m) {
            ProductCover(set: product.set, width: .thumb)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(product.set.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                FlowLayout(spacing: Spacing.xxs) {
                    Pill(text: t("products.kinds.\(product.set.kind.rawValue)"))
                    if product.isDeck { Pill(text: t("products.tab.deck"), tint: .accentColor) }
                    if product.copies > 1 { Pill(text: "×\(product.copies)") }
                    TagPills(tagIds: product.tags)
                }
                Text(product.completeness >= 1
                     ? t("products.tab.complete")
                     : t("products.tab.missing", ["count": product.missingCopies]))
                    .font(.caption)
                    .foregroundStyle(product.completeness >= 1 ? Theme.success : Theme.warning)
            }
            Spacer(minLength: 0)
            Text(t("products.tab.cardCount", ["count": product.totalCards]))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Spacing.xxs)
    }
}
