import SwiftUI

/// Aperçu d'un deck généré avant de le créer. Pour un deck du meta ou officiel, on bascule
/// entre la liste complète et la version « avec mes cartes ».
struct GeneratedDeckView: View {
    let target: GenerationTarget

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var mode: GenerationMode = .owned
    @State private var deck: Loadable<GeneratedDeck> = .idle
    @State private var name = ""
    @State private var wishlistMissing = true
    @State private var saving = false
    @State private var createError: String?
    @State private var selected: CardLink?

    private var modesKey: String {
        if case .official = target { return "suggestions.generate.modesOfficial" }
        return "suggestions.generate.modes"
    }

    private var title: String {
        switch target {
        case .meta(_, let name): t("suggestions.generate.titleMeta", ["name": name])
        case .official(_, let name): t("suggestions.generate.titleOfficial", ["name": name])
        case .archetype(let archetype): t("suggestions.generate.titleArchetype", ["archetype": archetype])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if target.hasModes {
                        Picker("", selection: $mode) {
                            ForEach([GenerationMode.owned, .meta]) { m in
                                Text(t("\(modesKey).\(m.rawValue).label")).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(t("\(modesKey).\(mode.rawValue).hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LoadableView(state: deck, retry: load) { deck in
                        content(deck)
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let value = deck.value { createBar(value) }
            }
        }
        .task(id: mode) { await load() }
        .cardDetailSheet($selected)
    }

    private func load() async {
        if deck.value != nil { deck = .loading }
        deck = await .fetch(.idle) { try await app.api.generate(target, mode: mode) }
        if let value = deck.value { name = value.name }
    }

    // MARK: - Contenu

    @ViewBuilder
    private func content(_ deck: GeneratedDeck) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.s), GridItem(.flexible(), spacing: Spacing.s)], spacing: Spacing.s) {
            StatTile(
                label: t("suggestions.generate.summary.counts"),
                value: "\(deck.counts.MAIN) / \(deck.counts.EXTRA) / \(deck.counts.SIDE)",
                tint: deck.complete ? Theme.success : Theme.warning)
            StatTile(
                label: t("suggestions.generate.summary.playable"),
                value: deck.complete
                    ? t("suggestions.generate.summary.yes")
                    : t("suggestions.generate.summary.missingMain", ["count": 40 - deck.counts.MAIN]),
                tint: deck.complete ? Theme.success : Theme.warning,
                systemImage: deck.complete ? "checkmark" : "exclamationmark.triangle")
            StatTile(
                label: t("suggestions.generate.summary.toBuy"),
                value: deck.missingCopies > 0
                    ? t("suggestions.generate.summary.toBuyValue", ["count": deck.missingCopies])
                    : t("suggestions.generate.summary.nothing"),
                tint: deck.missingCopies > 0 ? Theme.warning : Theme.success)
            StatTile(
                label: t("suggestions.generate.summary.cost"),
                value: L10n.shared.price(deck.missingCost),
                systemImage: "eurosign")
        }

        if deck.mode != GenerationMode.meta.rawValue {
            HStack(alignment: .top, spacing: Spacing.m) {
                ScoreBadge(score: deck.score.score)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(deck.score.playable
                         ? t("suggestions.generate.status.playable")
                         : deck.complete ? t("suggestions.generate.status.fragile") : t("suggestions.generate.status.incomplete"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(deck.score.playable ? Theme.success : Theme.warning)
                    ScoreBreakdown(score: deck.score)
                }
            }
        }

        if !deck.notes.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(deck.notes, id: \.self) { note in
                    Text("· \(note)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        ForEach(DeckZone.allCases) { zone in
            let cards = deck.cards.filter { $0.zone == zone }
            if !cards.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SectionHeader(t("common.zones.\(zone.rawValue)")) {
                        Text(t("suggestions.generate.zoneCount", ["count": deck.counts[zone]]))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: GridWidth.compactCard), spacing: Spacing.s)], spacing: Spacing.m) {
                        ForEach(cards, id: \.card.id) { entry in
                            Button { selected = CardLink(cardId: entry.card.id) } label: {
                                GeneratedCardTile(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }

        DeckGuideView(
            cards: deck.cards.map { DeckCardEntry(cardId: $0.card.id, zone: $0.zone, quantity: $0.quantity) },
            name: deck.name
        ) { selected = CardLink(cardId: $0) }
    }

    // MARK: - Création

    private func createBar(_ deck: GeneratedDeck) -> some View {
        VStack(spacing: Spacing.m) {
            TextField(t("suggestions.generate.nameLabel"), text: $name)
                .padding(Spacing.m)
                .background(.fill.tertiary, in: .rect(cornerRadius: Radius.s, style: .continuous))
            if deck.missingCopies > 0 {
                Toggle(t("suggestions.generate.wishlistMissing", ["count": deck.missingCopies]), isOn: $wishlistMissing)
                    .font(.footnote)
            }
            if let createError {
                Text(createError).font(.footnote).foregroundStyle(Theme.danger)
            }
            Button {
                Task { await create(deck) }
            } label: {
                Group {
                    if saving { ProgressView() } else { Label(t("suggestions.generate.create"), systemImage: "plus") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(saving)
        }
        .padding(Spacing.l)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.l, style: .continuous))
        .padding(.horizontal, Spacing.m)
        .padding(.bottom, Spacing.xxs)
    }

    private func create(_ deck: GeneratedDeck) async {
        saving = true
        createError = nil
        defer { saving = false }
        do {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let created = try await app.api.createDeck(CreateDeckBody(
                name: String((trimmed.isEmpty ? deck.name : trimmed).prefix(80)),
                cards: deck.cards.map { DeckCardEntry(cardId: $0.card.id, zone: $0.zone, quantity: $0.quantity) }))
            if wishlistMissing {
                // Une ligne de wishlist par carte (toutes zones confondues), liée au nouveau deck
                var byCard: [Int: Int] = [:]
                for c in deck.cards where c.missing > 0 { byCard[c.card.id, default: 0] += c.missing }
                for (cardId, quantity) in byCard {
                    try? await app.api.addToWishlist(AddWishlistBody(cardId: cardId, deckId: created.id, quantity: min(quantity, 3)))
                }
                if !byCard.isEmpty { app.wishlistChanged() }
            }
            dismiss()
            app.openDeck(created.id)
        } catch {
            createError = error.localizedDescription
        }
    }
}

private struct GeneratedCardTile: View {
    let entry: GeneratedDeckCard

    var body: some View {
        VStack(spacing: 3) {
            CardTile(card: entry.card, quantity: entry.quantity, missing: entry.missing)
            if entry.source.isLabeled {
                Text(t("suggestions.generate.sources.\(entry.source.rawValue)"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            entry.missing > 0
                ? t("suggestions.generate.card.toBuy", ["count": entry.missing])
                : t("suggestions.generate.card.allOwned"))
    }
}
