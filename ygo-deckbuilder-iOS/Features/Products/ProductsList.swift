import SwiftUI

/// Produits ajoutés à la collection (structure decks, tins, coffrets…).
struct ProductsList<Header: View>: View {
    let header: Header
    let onAdd: () -> Void

    @Environment(AppState.self) private var app
    @State private var products: Loadable<[OwnedProduct]> = .idle

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            LoadableView(state: products, retry: load) { products in
                if products.isEmpty {
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
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .task(id: app.collectionVersion) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        products = await .fetch(products) { try await app.api.ownedProducts() }
    }
}

private struct OwnedProductRow: View {
    let product: OwnedProduct

    var body: some View {
        HStack(spacing: 12) {
            ProductCover(set: product.set, width: .thumb)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(product.set.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Pill(text: t("products.kinds.\(product.set.kind.rawValue)"))
                    if product.isDeck { Pill(text: t("products.tab.deck"), tint: .accentColor) }
                    if product.copies > 1 { Pill(text: "×\(product.copies)") }
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
    }
}
