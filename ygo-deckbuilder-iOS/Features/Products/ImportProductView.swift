import SwiftUI

/// Ajout d'un produit entier : galerie filtrable par type, puis confirmation (exemplaires, langue).
struct ImportProductView: View {
    /// Produit ajouté (id de l'OwnedProduct) : la collection ouvre sa fiche.
    var onImported: (String) -> Void

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ProductKind?
    @State private var query = ""
    @State private var sets: Loadable<[CardSet]> = .idle
    @State private var chosen: CardSet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.s) {
                            kindChip(nil)
                            ForEach(ProductKind.allCases) { kindChip($0) }
                        }
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.xxs)
                    }
                    .scrollClipDisabled()

                    LoadableView(state: sets, retry: load) { sets in
                        if sets.isEmpty {
                            ContentUnavailableView(t("collection.import.noResults"), systemImage: "shippingbox")
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: GridWidth.product), spacing: Spacing.m)], spacing: Spacing.m) {
                                ForEach(sets) { set in
                                    Button { chosen = set } label: { ProductTile(set: set) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, Spacing.l)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(t("collection.import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: t("collection.import.searchPlaceholder"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
                }
            }
            .task(id: "\(kind?.rawValue ?? "ALL")|\(query)") {
                if !query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
                guard !Task.isCancelled else { return }
                await load()
            }
            .sheet(item: $chosen) { set in
                ImportConfirmSheet(set: set) { productId in
                    dismiss()
                    onImported(productId)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func load() async {
        sets = await .fetch(sets) { try await app.api.sets(q: query, kind: kind) }
    }

    private func kindChip(_ value: ProductKind?) -> some View {
        FilterChip(t("collection.import.kinds.\(value?.rawValue ?? "ALL")"), isOn: kind == value) { kind = value }
    }
}

private struct ProductTile: View {
    let set: CardSet

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ProductCover(set: set)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
            Text(set.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
            HStack(spacing: Spacing.xxs) {
                if let code = set.code { Text(code).font(.caption2.monospaced()) }
                if let date = set.tcgDate { Text(String(date.prefix(4))).font(.caption2) }
                Spacer()
                Text(t("collection.import.cardCount", ["count": set.cardCount])).font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .tileSurface(padding: Spacing.s + 2, radius: Radius.s + 4)
    }
}

private struct ImportConfirmSheet: View {
    let set: CardSet
    let onDone: (String) -> Void

    @Environment(AppState.self) private var app
    @State private var copies = 1
    @State private var language: CardLanguage = L10n.shared.current.cardLanguage
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ProductCover(set: set, width: .thumb)
                            .frame(width: 80, height: 80)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(set.name).font(.headline)
                            if let date = set.tcgDate {
                                Text(t("collection.import.confirm.releasedOn", ["date": L10n.shared.date(date)]))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(L10n.shared.rich("collection.import.confirm.description", ["count": set.cardCount]))
                        .font(.footnote)
                }
                Section {
                    Stepper(value: $copies, in: 1...10) {
                        LabeledContent(t("collection.import.confirm.copiesEach"), value: "\(copies)")
                    }
                    Picker(t("collection.import.confirm.language"), selection: $language) {
                        ForEach(CardLanguage.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.danger) }
                }
                Section {
                    Button {
                        Task { await add() }
                    } label: {
                        Group {
                            if saving { ProgressView() } else { Text(t("collection.import.confirm.add")) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(saving)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle(t("products.kinds.\(set.kind.rawValue)"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func add() async {
        saving = true
        defer { saving = false }
        do {
            let result = try await app.api.importSet(ImportSetBody(setName: set.name, copies: copies, language: language))
            app.collectionChanged()
            onDone(result.productId)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
