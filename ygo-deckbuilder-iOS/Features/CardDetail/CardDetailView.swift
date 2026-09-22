import SwiftUI

/// Ouverture d'une fiche : depuis une grille, un deck, un scan (code imprimé → impression
/// et langue présélectionnées), ou depuis les interactions d'une autre carte.
struct CardLink: Hashable, Identifiable {
    let cardId: Int
    var printHint: String?
    var id: Int { cardId }
}

/// Fiche carte en feuille, avec sa propre pile de navigation (interactions → autre carte).
struct CardDetailSheet: View {
    let link: CardLink
    /// Contexte deck builder : bloc « Dans ce deck » avec + / − par zone.
    var builder: DeckBuilderModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CardDetailView(link: link, builder: builder)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
                    }
                }
                .navigationDestination(for: CardLink.self) { next in
                    CardDetailView(link: next, builder: builder)
                }
        }
        .presentationDragIndicator(.visible)
    }
}

extension View {
    /// Présente la fiche d'une carte.
    func cardDetailSheet(_ link: Binding<CardLink?>, builder: DeckBuilderModel? = nil) -> some View {
        sheet(item: link) { CardDetailSheet(link: $0, builder: builder) }
    }
}

struct CardDetailView: View {
    let link: CardLink
    var builder: DeckBuilderModel?

    @Environment(AppState.self) private var app
    @State private var card: Loadable<CardDetail> = .idle
    @State private var zoomed = false

    var body: some View {
        ScrollView {
            LoadableView(state: card, retry: load) { card in
                content(card)
            }
            .padding()
        }
        .navigationTitle(card.value?.name ?? t("cards.detail.fallbackTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: app.collectionVersion) { await load() }
        .fullScreenCover(isPresented: $zoomed) {
            if let value = card.value { ZoomedCard(card: value.summary) }
        }
    }

    private func load() async {
        card = await .fetch(card) { try await app.api.card(link.cardId) }
    }

    @ViewBuilder
    private func content(_ card: CardDetail) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 16) {
                Button { zoomed = true } label: {
                    CardArt(card: card.summary, width: .medium)
                        .frame(width: 150)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityHint(t("ios.card.zoom"))

                CardFacts(card: card)
            }

            Text(card.desc)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let builder, card.category != .skill, card.category != .token {
                DeckCardActions(card: card.summary, builder: builder)
            }

            AddToCollectionSection(card: card, printHint: link.printHint)
            AddToWishlistSection(card: card)

            if !card.prints.isEmpty {
                PrintsSection(prints: card.prints)
            }

            CardInteractionsSection(cardId: card.id)
        }
    }
}

/// Type, attribut, niveau, ATK/DEF, banlist, possession et prix.
private struct CardFacts: View {
    let card: CardDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                Pill(text: card.type, tint: Theme.color(for: card.summary))
                if let attribute = card.attribute { Pill(text: attribute) }
                if let race = card.race { Pill(text: race) }
                if let level = card.level, card.category == .monster {
                    Pill(text: t("cards.detail.level", ["level": level]), systemImage: "star.fill")
                }
                if let link = card.linkVal { Pill(text: "LINK-\(link)") }
                if let scale = card.scale { Pill(text: t("cards.detail.scale", ["scale": scale])) }
                if let ban = card.banTcg {
                    Pill(
                        text: t("cards.detail.banTcg", ["status": banLabel(ban)]),
                        tint: ban == "Limited" || ban == "Semi-Limited" ? Theme.warning : Theme.danger)
                }
            }

            if card.category == .monster, card.atk != nil || card.def != nil {
                HStack(spacing: 16) {
                    stat("ATK", card.atk.map(String.init) ?? "?")
                    if card.linkVal == nil { stat("DEF", card.def.map(String.init) ?? "?") }
                }
            }

            Text(L10n.shared.rich("cards.detail.ownedPrice", [
                "owned": card.ownedQuantity ?? 0,
                "price": L10n.shared.price(card.priceCardmarket),
            ]))
            .font(.subheadline)

            if let archetype = card.archetype {
                Label(archetype, systemImage: "tag")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
        }
    }
}

func banLabel(_ status: String) -> String {
    let key = "cards.ban.\(status)"
    return L10n.shared.has(key) ? t(key) : status
}

private struct PrintsSection: View {
    let prints: [CardPrint]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 0) {
                ForEach(prints) { print in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(print.printCode).font(.subheadline.monospaced())
                            Text("\(print.rarity) · \(print.setName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text(L10n.shared.price(print.price))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        } label: {
            Text(t("cards.detail.prints", ["count": prints.count]))
                .font(.headline)
        }
    }
}

/// Visuel en grand (plein écran, toucher pour fermer).
private struct ZoomedCard: View {
    let card: CardSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CardArt(card: card, width: .large)
                .padding(24)
        }
        .onTapGesture { dismiss() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(t("common.actions.close"))
    }
}
