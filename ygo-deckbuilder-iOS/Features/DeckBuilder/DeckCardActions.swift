import SwiftUI

/// Bloc « Dans ce deck » de la fiche carte : exemplaires par zone, + / −, limites et possession.
struct DeckCardActions: View {
    let card: CardSummary
    let builder: DeckBuilderModel
    @State private var error: String?

    private var zones: [DeckZone] { card.isExtraDeck ? [.extra, .side] : [.main, .side] }

    var body: some View {
        let total = builder.totalCopies(of: card.id)
        let limit = builder.limit(for: card)
        let owned = card.owned

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(t("deckBuilder.actions.inDeck")).font(.headline)
                Text(t("deckBuilder.actions.copies", ["total": total, "limit": limit])
                    + (!builder.isOCG && card.banTcg != nil ? " · \(banLabel(card.banTcg!))" : ""))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(t("deckBuilder.actions.owned", ["owned": owned, "toBuy": max(0, total - owned)]))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(owned >= total ? Theme.success : Theme.danger)
            }

            ForEach(zones) { zone in
                let n = builder.quantity(of: card.id, in: zone)
                let label = t("common.zones.\(zone.rawValue)")
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.subheadline.weight(.medium))
                        Text(t("deckBuilder.actions.zoneCount", [
                            "count": builder.count(zone), "max": DeckRules.range(zone).upperBound,
                        ]))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(t("deckBuilder.actions.removeOne", ["zone": label]), systemImage: "minus") {
                        error = nil
                        builder.removeOne(card.id, from: zone)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .disabled(n == 0)

                    Text("\(n)")
                        .font(.title3.bold().monospacedDigit())
                        .frame(minWidth: 24)
                        .contentTransition(.numericText())

                    Button(t("deckBuilder.actions.addOne", ["zone": label]), systemImage: "plus") {
                        error = builder.add(card, to: zone)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glassProminent)
                    .disabled(total >= limit)
                }
                .padding(10)
                .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            }

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor.opacity(0.3)))
        .sensoryFeedback(.selection, trigger: total)
        .animation(.snappy, value: total)
    }
}
