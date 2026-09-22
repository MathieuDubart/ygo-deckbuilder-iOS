import SwiftUI
import UIKit

/// Fiche d'un produit de la collection : son contenu (pour le reconstituer), ce qui manque,
/// et — pour les decks — le guide de jeu et la création d'un deck.
struct ProductDetailView: View {
    let productId: String

    enum Tab: Hashable { case content, guide }

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var product: Loadable<OwnedProductDetail> = .idle
    @State private var tab: Tab = .content
    @State private var missingOnly = false
    @State private var selected: CardLink?
    @State private var confirmRemove = false
    @State private var copied = false
    @State private var actionError: String?
    @State private var creating = false

    var body: some View {
        ScrollView {
            LoadableView(state: product, retry: load) { product in
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header(product)
                    if product.isDeck {
                        Picker("", selection: $tab) {
                            Label(t("products.dialog.tabs.content"), systemImage: "checklist").tag(Tab.content)
                            Label(t("products.dialog.tabs.guide"), systemImage: "book").tag(Tab.guide)
                        }
                        .pickerStyle(.segmented)
                    }
                    if tab == .guide && product.isDeck {
                        Text(t("products.dialog.guideIntro"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        DeckGuideView(cards: deckCards(product), name: product.set.name) { selected = CardLink(cardId: $0) }
                    } else {
                        content(product)
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
        }
        .navigationTitle(product.value?.set.name ?? t("products.dialog.fallbackTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: app.collectionVersion) { await load() }
        .cardDetailSheet($selected)
        .confirmationDialog(
            t("products.dialog.header.confirmRemove", ["name": product.value?.set.name ?? ""]),
            isPresented: $confirmRemove, titleVisibility: .visible
        ) {
            Button(t("products.dialog.header.remove"), role: .destructive) {
                Task { await remove(removeCards: false) }
            }
            Button(t("ios.products.removeWithCards"), role: .destructive) {
                Task { await remove(removeCards: true) }
            }
        } message: {
            Text(t("products.dialog.header.removeCardsToo", ["count": product.value?.totalCards ?? 0]))
        }
    }

    private func load() async {
        product = await .fetch(product) { try await app.api.ownedProduct(productId) }
    }

    // MARK: - En-tête

    @ViewBuilder
    private func header(_ p: OwnedProductDetail) -> some View {
        HStack(alignment: .top, spacing: Spacing.l) {
            ProductCover(set: p.set, width: .medium)
                .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Pill(text: t("products.kinds.\(p.set.kind.rawValue)"), tint: .accentColor)
                Text(t("products.dialog.header.productCount", ["count": p.copies, "language": p.language.rawValue]))
                    .font(.subheadline)
                Text(t("products.dialog.header.cardCount", ["total": p.totalCards, "distinct": p.distinctCards]))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(
                    t(p.quantitiesVerified ? "products.dialog.header.verified" : "products.dialog.header.unverified"),
                    systemImage: p.quantitiesVerified ? "checkmark.seal.fill" : "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(p.quantitiesVerified ? Theme.success : Theme.warning)
                    .accessibilityHint(p.quantitiesVerified ? "" : t("products.dialog.header.unverifiedHint"))
                Text(t("products.dialog.header.addedOn", ["date": L10n.shared.date(p.addedAt)]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Text(p.completeness >= 1
             ? t("products.dialog.header.complete")
             : t("products.dialog.header.missing", ["count": p.missingCopies]))
            .font(.subheadline)
            .foregroundStyle(p.completeness >= 1 ? Theme.success : Theme.warning)

        GlassEffectContainer(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                if p.isDeck {
                    Button {
                        Task { await createDeck(p) }
                    } label: {
                        Label(t("products.dialog.header.createDeck"), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(creating)
                }
                Button {
                    UIPasteboard.general.string = listAsText(p)
                    copied = true
                } label: {
                    Label(
                        t(copied ? "products.dialog.header.listCopied" : "products.dialog.header.copyList"),
                        systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.glass)
                ShareLink(item: listAsText(p)) {
                    Label(t("ios.common.share"), systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                Button(role: .destructive) {
                    confirmRemove = true
                } label: {
                    Label(t("products.dialog.header.remove"), systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
            }
        }
        .sensoryFeedback(.success, trigger: copied)

        if let actionError {
            Text(actionError).font(.footnote).foregroundStyle(Theme.danger)
        }
    }

    // MARK: - Contenu

    private static let groups: [(key: String, match: (OwnedProductCard) -> Bool)] = [
        ("MONSTER", { $0.zone == .main && $0.card.category == .monster }),
        ("SPELL", { $0.zone == .main && $0.card.category == .spell }),
        ("TRAP", { $0.zone == .main && $0.card.category == .trap }),
        ("EXTRA", { $0.zone == .extra }),
        ("OTHER", { $0.zone == .main && ![CardCategory.monster, .spell, .trap].contains($0.card.category) }),
    ]

    @ViewBuilder
    private func content(_ p: OwnedProductDetail) -> some View {
        let missingCount = p.cards.filter { $0.owned < $0.needed }.count
        Text(t(p.copies > 1 ? "products.dialog.content.forCopies" : "products.dialog.content.all", ["count": p.copies]))
            .font(.footnote)
            .foregroundStyle(.secondary)
        if missingCount > 0 {
            Toggle(t("products.dialog.content.missingOnly", ["count": missingCount]), isOn: $missingOnly)
        }
        ForEach(Self.groups, id: \.key) { group in
            let cards = p.cards.filter(group.match).filter { !missingOnly || $0.owned < $0.needed }
            if !cards.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader(t("products.dialog.groups.\(group.key)")) {
                        Text("\(cards.reduce(0) { $0 + $1.needed })")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(cards, id: \.card.id) { c in
                        Button { selected = CardLink(cardId: c.card.id, printHint: c.printCode) } label: {
                            CardRow(card: c.card, subtitle: "\(c.printCode) · \(c.rarity)") {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(c.needed)×").font(.subheadline.bold().monospacedDigit())
                                    Text(t("products.dialog.content.ownedOf", ["owned": c.owned, "needed": c.needed]))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(c.owned >= c.needed ? Theme.success : Theme.danger)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Liste de deck à partir du produit (bornée par les règles : 3 exemplaires, 60 / 15).
    private func deckCards(_ p: OwnedProductDetail) -> [DeckCardEntry] {
        var room: [DeckZone: Int] = [.main: 60, .extra: 15]
        return p.cards.compactMap { c in
            let quantity = min(c.quantity, DeckRules.maxCopies(for: c.card.banTcg), room[c.zone] ?? 0)
            guard quantity > 0 else { return nil }
            room[c.zone, default: 0] -= quantity
            return DeckCardEntry(cardId: c.card.id, zone: c.zone, quantity: quantity)
        }
    }

    private func listAsText(_ p: OwnedProductDetail) -> String {
        let name = p.set.code.map { "\(p.set.name) (\($0))" } ?? p.set.name
        var lines = [t("products.dialog.text.header", ["name": name, "count": p.copies])]
        for group in Self.groups {
            let cards = p.cards.filter(group.match)
            guard !cards.isEmpty else { continue }
            lines.append("")
            lines.append("\(t("products.dialog.groups.\(group.key)")) (\(cards.reduce(0) { $0 + $1.needed }))")
            for c in cards { lines.append("\(c.needed)x \(c.card.name) — \(c.printCode) (\(c.rarity))") }
        }
        return lines.joined(separator: "\n")
    }

    private func createDeck(_ p: OwnedProductDetail) async {
        creating = true
        actionError = nil
        defer { creating = false }
        do {
            let deck = try await app.api.createDeck(CreateDeckBody(name: String(p.set.name.prefix(80)), cards: deckCards(p)))
            app.openDeck(deck.id)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func remove(removeCards: Bool) async {
        do {
            try await app.api.removeProduct(productId, removeCards: removeCards)
            app.collectionChanged()
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
