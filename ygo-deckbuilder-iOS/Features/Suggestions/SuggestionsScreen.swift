import SwiftUI

/// Suggestions : decks prêts à jouer (100 % tes cartes), decks du meta, decks officiels
/// (structure, starters, coffrets) et un deck auto par archétype de la collection.
struct SuggestionsScreen: View {
    @Environment(AppState.self) private var app
    @State private var playable: Loadable<[PlayableDeck]> = .idle
    @State private var meta: Loadable<[MetaDeckSuggestion]> = .idle
    @State private var archetypes: Loadable<[ArchetypeSuggestion]> = .idle
    @State private var officialKind: OfficialDeckKind?
    @State private var official: Loadable<[OfficialDeckSuggestion]> = .idle
    @State private var officialShown = 6
    @State private var target: GenerationTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(t("suggestions.page.description"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    section(t("suggestions.page.sections.playable"), systemImage: "checkmark.shield") { playableSection }
                    section(t("suggestions.page.sections.meta"), systemImage: "trophy") { metaSection }
                    section(t("suggestions.page.sections.official"), systemImage: "shippingbox") { officialSection }
                    section(t("suggestions.page.sections.archetypes"), systemImage: "sparkles") { archetypeSection }
                }
                .padding()
            }
            .navigationTitle(t("suggestions.page.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SettingsButton() }
            }
            .refreshable { await loadAll() }
        }
        .task(id: app.collectionVersion) { await loadAll() }
        .task(id: officialKind) {
            officialShown = 6
            official = await .fetch(official) { try await app.api.officialDecks(kind: officialKind) }
        }
        .sheet(item: $target) { GeneratedDeckView(target: $0) }
    }

    private func loadAll() async {
        // Le calcul des decks jouables est le plus long (~1 s) : en dernier
        await loadMeta()
        await loadOfficial()
        await loadArchetypes()
        await loadPlayable()
    }

    private func loadPlayable() async { playable = await .fetch(playable) { try await app.api.playableDecks() } }
    private func loadMeta() async { meta = await .fetch(meta) { try await app.api.metaSuggestions() } }
    private func loadArchetypes() async { archetypes = await .fetch(archetypes) { try await app.api.archetypeSuggestions() } }
    private func loadOfficial() async { official = await .fetch(official) { try await app.api.officialDecks(kind: officialKind) } }

    private func section(_ title: String, systemImage: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
    }

    // MARK: - Prêts à jouer

    @ViewBuilder
    private var playableSection: some View {
        LoadableView(state: playable, retry: loadPlayable) { decks in
            if decks.isEmpty {
                ContentUnavailableView {
                    Label(t("suggestions.playable.empty.title"), systemImage: "shippingbox")
                } description: {
                    Text(t("suggestions.playable.empty.description"))
                } actions: {
                    Button(t("suggestions.playable.empty.action")) { app.selectedTab = .collection }
                        .buttonStyle(.glass)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(decks.enumerated()), id: \.offset) { index, deck in
                            PlayableDeckCard(deck: deck, best: index == 0) { target = deck.target }
                                .frame(width: 290)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Meta

    @ViewBuilder
    private var metaSection: some View {
        LoadableView(state: meta, retry: loadMeta) { decks in
            if decks.isEmpty {
                ContentUnavailableView(t("suggestions.meta.empty.title"), systemImage: "trophy",
                                       description: Text(t("suggestions.meta.empty.description")))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(decks) { deck in
                        MetaDeckCard(deck: deck) { target = .meta(metaDeckId: deck.metaDeckId, name: deck.name) }
                    }
                }
            }
        }
    }

    // MARK: - Officiels

    @ViewBuilder
    private var officialSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                officialChip(nil)
                ForEach(OfficialDeckKind.allCases) { officialChip($0) }
            }
        }
        LoadableView(state: official, retry: loadOfficial) { decks in
            if decks.isEmpty {
                ContentUnavailableView(t("suggestions.official.empty.title"), systemImage: "shippingbox",
                                       description: Text(t("suggestions.official.empty.description")))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(decks.prefix(officialShown)) { deck in
                        OfficialDeckCard(deck: deck) {
                            target = .official(productDeckId: deck.productDeckId, name: deck.displayName)
                        }
                    }
                }
                if decks.count > officialShown {
                    Button(t("suggestions.official.showMore", ["count": decks.count - officialShown])) {
                        withAnimation { officialShown += 9 }
                    }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func officialChip(_ kind: OfficialDeckKind?) -> some View {
        FilterChip(t("suggestions.official.filters.\(kind?.rawValue ?? "ALL")"), isOn: officialKind == kind) {
            officialKind = kind
        }
    }

    // MARK: - Archétypes

    @ViewBuilder
    private var archetypeSection: some View {
        LoadableView(state: archetypes, retry: loadArchetypes) { items in
            if items.isEmpty {
                Text(t("suggestions.page.archetypesEmpty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            target = .archetype(item.archetype)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.archetype).font(.subheadline.weight(.semibold))
                                Text(t("suggestions.page.archetypeStats", ["cards": item.distinctCards, "copies": item.totalCopies]))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Cartes de suggestions

private struct PlayableDeckCard: View {
    let deck: PlayableDeck
    let best: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                HStack(spacing: -22) {
                    ForEach(Array(deck.highlights.enumerated()), id: \.offset) { index, card in
                        let offset = Double(index) - Double(deck.highlights.count - 1) / 2
                        CardArt(card: card, width: .thumb)
                            .frame(width: 70)
                            .rotationEffect(.degrees(offset * 7))
                            .offset(y: abs(offset) * 6)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(.top, 12)

                HStack(spacing: 4) {
                    if best { Pill(text: t("suggestions.playable.best"), tint: .accentColor) }
                    switch deck.target {
                    case .official:
                        Pill(text: t("suggestions.playable.official"))
                    default:
                        if let tier = deck.tier {
                            Pill(text: t("suggestions.playable.metaTier", ["tier": tier]))
                        } else {
                            Pill(text: t("suggestions.playable.homebrew"))
                        }
                    }
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deck.name).font(.headline).lineLimit(1)
                    Label(t("suggestions.playable.composition", ["main": deck.counts.MAIN, "extra": deck.counts.EXTRA]),
                          systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(Theme.success)
                }
                Spacer()
                ScoreBadge(score: deck.score.score)
            }

            ScoreBreakdown(score: deck.score)

            if best {
                openButton.buttonStyle(.glassProminent)
            } else {
                openButton.buttonStyle(.glass)
            }
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(best ? Color.accentColor.opacity(0.5) : .clear))
    }

    private var openButton: some View {
        Button(action: onOpen) {
            Label(t("suggestions.playable.open"), systemImage: "wand.and.stars")
                .frame(maxWidth: .infinity)
        }
    }
}

private struct MetaDeckCard: View {
    let deck: MetaDeckSuggestion
    let onBuild: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RemoteImage([deck.coverURL], width: .medium) { Rectangle().fill(.fill.tertiary) }
                    .frame(height: 90)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                HStack(spacing: 4) {
                    if let tier = deck.tier { Pill(text: t("suggestions.meta.card.tier", ["tier": tier]), tint: .accentColor) }
                    if deck.source == "tournaments", let share = deck.share {
                        Pill(text: t("suggestions.meta.card.share", ["share": L10n.shared.percent(share)]), tint: .white)
                    }
                }
                .padding(8)
            }
            .clipShape(.rect(cornerRadius: 14))

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deck.name).font(.headline).lineLimit(1)
                    Text(deck.listCount > 0 ? t("suggestions.meta.card.listCount", ["count": deck.listCount]) : t("suggestions.meta.card.imported"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let variant = deck.variants.first {
                        Text(t("suggestions.meta.card.variant", ["name": variant]))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                CoverageRing(value: deck.coverage)
            }

            if deck.missing.isEmpty {
                Label(t("suggestions.meta.card.playable"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.success)
            } else {
                Text(L10n.shared.rich("suggestions.meta.card.missing", [
                    "owned": deck.ownedCopies, "required": deck.requiredCopies,
                    "cost": L10n.shared.price(deck.estimatedCostToComplete),
                ]))
                .font(.caption)
            }

            Button(action: onBuild) {
                Label(t("suggestions.meta.card.build"), systemImage: "wand.and.stars").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
    }
}

private struct OfficialDeckCard: View {
    let deck: OfficialDeckSuggestion
    let onBuild: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProductCover(set: deck.product, width: .tile)
                .frame(width: 84, height: 100)
            VStack(alignment: .leading, spacing: 6) {
                if let deckName = deck.deckName {
                    Text(deckName).font(.headline).lineLimit(2)
                    Text(deck.product.name).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text(deck.product.name).font(.headline).lineLimit(2)
                }
                HStack(spacing: 4) {
                    if let code = deck.product.code { Pill(text: code) }
                    if let archetype = deck.archetype { Pill(text: archetype, tint: .accentColor) }
                    if deck.productOwned { Pill(text: t("suggestions.official.owned"), tint: Theme.success, systemImage: "checkmark") }
                }
                if deck.coverage >= 1 {
                    Text(t("suggestions.meta.card.playable")).font(.caption).foregroundStyle(Theme.success)
                } else {
                    Text(L10n.shared.rich("suggestions.meta.card.missing", [
                        "owned": deck.ownedCopies, "required": deck.requiredCopies,
                        "cost": L10n.shared.price(deck.estimatedCostToComplete),
                    ]))
                    .font(.caption)
                }
                Button(action: onBuild) {
                    Label(t("suggestions.meta.card.build"), systemImage: "wand.and.stars")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
            CoverageRing(value: deck.coverage, size: 46)
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 22))
    }
}
