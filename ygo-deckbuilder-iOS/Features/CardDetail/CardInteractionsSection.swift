import SwiftUI

/// Ce que la carte fait avec le reste du catalogue (et ce que les autres font avec elle).
/// Toucher une carte ouvre sa fiche dans la même pile de navigation.
struct CardInteractionsSection: View {
    let cardId: Int

    @Environment(AppState.self) private var app
    @State private var data: Loadable<CardInteractions> = .idle
    @State private var direction: CardInteractionGroup.Direction?
    @State private var onlyMine = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t("cards.interactions.title")).font(.headline)
                if let owned = data.value?.ownedLinked, owned > 0 {
                    Pill(text: t("cards.interactions.ownedLinked", ["count": owned]), tint: Theme.success)
                }
            }

            switch data {
            case .loaded(let value):
                content(value)
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(.secondary)
            default:
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task(id: cardId) {
            data = await .fetch(data) { try await app.api.interactions(cardId) }
        }
    }

    @ViewBuilder
    private func content(_ value: CardInteractions) -> some View {
        let known = value.groups.filter { $0.verb != .unknown }
        let out = known.filter { $0.direction == .out }
        let inc = known.filter { $0.direction == .in }
        let current = direction ?? (out.isEmpty ? .in : .out)
        let groups = (current == .out ? out : inc)
            .map { group in onlyMine ? group.filteringOwned() : group }
            .filter { !$0.cards.isEmpty }

        if out.isEmpty && inc.isEmpty {
            Text(t(value.indexed ? "cards.interactions.emptyIndexed" : "cards.interactions.emptyIndexing"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Picker("", selection: Binding(get: { current }, set: { direction = $0 })) {
                Text("\(t("cards.interactions.tabs.out")) (\(out.count))").tag(CardInteractionGroup.Direction.out)
                Text("\(t("cards.interactions.tabs.in")) (\(inc.count))").tag(CardInteractionGroup.Direction.in)
            }
            .pickerStyle(.segmented)

            Toggle(t("cards.interactions.onlyMine"), isOn: $onlyMine)
                .font(.subheadline)

            if groups.isEmpty {
                Text(t(onlyMine ? "cards.interactions.noneMine" : "cards.interactions.none"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    InteractionGroupRow(group: group)
                }
            }
        }

        if current == .out, value.generic.contains(where: { $0.verb != .unknown }) {
            Text(t("cards.interactions.generic", [
                "list": value.generic
                    .filter { $0.verb != .unknown }
                    .map { "\(t("cards.interactions.out.\($0.verb.rawValue)").lowercased()) \($0.target)" }
                    .joined(separator: " · "),
            ]))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

private struct InteractionGroupRow: View {
    let group: CardInteractionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(t("cards.interactions.\(group.direction == .out ? "out" : "in").\(group.verb.rawValue)"))
                    .font(.subheadline.weight(.semibold))
                if let target = group.target {
                    Text(target).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if group.direction == .in, group.precision == .precise {
                    Text(t("cards.interactions.byTraits"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHint(t("cards.interactions.byTraitsTitle"))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(group.cards) { card in
                        NavigationLink(value: CardLink(cardId: card.id)) {
                            VStack(spacing: 4) {
                                CardTile(card: card, quantity: card.owned, dimmed: card.ownedQuantity == 0)
                                    .frame(width: 64)
                                Text(card.name)
                                    .font(.system(size: 10))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 70)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    let more = group.total - group.cards.count
                    if more > 0 {
                        Text("+\(more)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 44)
                    }
                }
            }
        }
    }
}

private extension CardInteractionGroup {
    func filteringOwned() -> CardInteractionGroup {
        CardInteractionGroup(
            direction: direction, verb: verb, target: target, precision: precision,
            cards: cards.filter { $0.owned > 0 }, total: total)
    }
}
