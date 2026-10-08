import SwiftUI

/// Visuel d'une carte au bon ratio, avec un repli coloré tant que l'image n'est pas là.
struct CardArt: View {
    let card: CardSummary
    var width: ImagePipeline.Width = .tile
    var dimmed = false
    /// Posée dans une pochette. Faux sur le plateau de duel, où les cartes face cachée n'en
    /// ont pas : deux tailles différentes dans la même case se verraient.
    var pocketed = true

    var body: some View {
        RemoteImage([card.imageURL], width: width) {
            ZStack {
                Theme.color(for: card).opacity(0.25)
                Text(card.name)
                    .font(.caption2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .aspectRatio(Theme.cardAspect, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
        .opacity(dimmed ? 0.3 : 1)
        .pocket(padding: pocketed ? 2 : 0, visible: pocketed)
        .accessibilityLabel(card.name)
    }
}

/// Tuile de grille : visuel + badge de quantité possédée.
struct CardTile: View {
    let card: CardSummary
    var quantity: Int?
    var dimmed = false
    var missing = 0

    var body: some View {
        CardArt(card: card, dimmed: dimmed)
            .overlay(alignment: .topTrailing) {
                if let quantity, quantity > 0 {
                    Text("×\(quantity)")
                        .codeStyle(11, weight: .bold)
                        .foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: .rect(cornerRadius: 3, style: .continuous))
                        .padding(5)
                }
            }
            .overlay(alignment: .bottom) {
                if missing > 0 {
                    Text(t("deckBuilder.zone.missingBadge"))
                        .codeStyle(9, weight: .bold)
                        .foregroundStyle(Theme.danger)
                        .padding(.bottom, 5)
                }
            }
    }
}

/// Ligne de liste : vignette, nom, type, et un contenu à droite.
struct CardRow<Trailing: View>: View {
    let card: CardSummary
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(card: CardSummary, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.card = card
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            CardArt(card: card, width: .thumb)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(subtitle ?? card.type)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.s)
            trailing()
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}

extension CardRow where Trailing == EmptyView {
    init(card: CardSummary, subtitle: String? = nil) {
        self.init(card: card, subtitle: subtitle) { EmptyView() }
    }
}

/// Visuel d'un produit (boîte HD Yugipedia, repli YGOPRODeck).
struct ProductCover: View {
    let set: CardSet
    var width: ImagePipeline.Width = .tile

    var body: some View {
        RemoteImage([set.imageURL, set.fallbackImageURL], width: width, contentMode: .fit) {
            ZStack {
                Rectangle().fill(.fill.tertiary)
                Image(systemName: "shippingbox")
                    .font(.title)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityLabel(set.name)
    }
}

/// Grille adaptative de cartes.
struct CardGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    var minWidth: CGFloat = GridWidth.card
    @ViewBuilder var cell: (Item) -> Cell

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: Spacing.m)], spacing: Spacing.l) {
            ForEach(items) { cell($0) }
        }
    }
}
