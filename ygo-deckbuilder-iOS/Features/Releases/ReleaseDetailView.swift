import SwiftUI

/// Une extension carte par carte : ce qu'on peut y tirer, ce qu'on a déjà, ce qui manque.
/// La bascule « toutes éditions » décide si une carte possédée ailleurs coche la case ici,
/// et elle est partagée avec la liste pour que les deux vues restent d'accord.
struct ReleaseDetailView: View {
    let setId: String
    @Binding var anyEdition: Bool

    enum Shown: String, Hashable, CaseIterable { case all, owned, missing }

    @Environment(AppState.self) private var app
    @State private var release: Loadable<ReleaseDetail> = .idle
    @State private var shown: Shown = .all
    @State private var rarity: String?
    @State private var selected: CardLink?

    var body: some View {
        ScrollView {
            LoadableView(state: release, retry: load) { detail in
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header(detail)
                    if detail.unrevealed {
                        ContentUnavailableView(
                            t("releases.unrevealed"), systemImage: "shippingbox",
                            description: Text(t("releases.unrevealedHint")))
                    } else {
                        progress(detail)
                        rarities(detail)
                        legend
                        filters(detail)
                        grid(detail)
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.section)
            }
        }
        .navigationTitle(release.value?.set.name ?? t("releases.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: app.collectionVersion) { await load() }
        .cardDetailSheet($selected)
    }

    private func load() async {
        release = await .fetch(release) { try await app.api.release(setId) }
    }

    // MARK: - En-tête

    private func header(_ detail: ReleaseDetail) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            ProductCover(set: detail.set, width: .medium)
                .frame(width: 92, height: 118)
            VStack(alignment: .leading, spacing: Spacing.s) {
                FlowLayout(spacing: Spacing.xxs) {
                    if let code = detail.set.code { Pill(text: code) }
                    Pill(text: t("products.kinds.\(detail.set.kind.rawValue)"))
                    ReleaseStatusPill(status: detail.status, daysUntil: detail.daysUntil)
                    if detail.ownedProduct { Pill(text: t("releases.sealed"), tint: Theme.success) }
                    TagPills(tagIds: detail.tags)
                }
                Text(detail.set.tcgDate.map(L10n.shared.date) ?? t("releases.noDate"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                TagPicker(attached: detail.tags) { tag, on in
                    try? await app.api.tagSet(tag.id, setId: detail.set.id, on: on)
                    app.tagsChanged()
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Avancement

    private func progress(_ detail: ReleaseDetail) -> some View {
        let owned = detail.progress.owned(anyEdition: anyEdition)
        let total = detail.progress.total(anyEdition: anyEdition)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(t(anyEdition ? "releases.progress.labelCards" : "releases.progress.labelPrints"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(owned) / \(total) · \(L10n.shared.percent(detail.progress.ratio(anyEdition: anyEdition)))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Meter(value: owned, total: total, height: 8)
            }
            HStack(spacing: Spacing.s) {
                StatTile(label: t("releases.stats.copies"), value: L10n.shared.number(detail.progress.copies))
                StatTile(label: t("releases.stats.ownedValue"), value: L10n.shared.price(detail.ownedValue))
                StatTile(
                    label: t("releases.stats.missingValue"), value: L10n.shared.price(detail.missingValue),
                    tint: Theme.warning)
            }
        }
    }

    /// Avancement par rareté : c'est là qu'on voit ce qui coince.
    @ViewBuilder
    private func rarities(_ detail: ReleaseDetail) -> some View {
        if detail.rarities.count > 1 {
            VStack(alignment: .leading, spacing: Spacing.s) {
                // L'API ne décompte les raretés que par impression : avec « toutes
                // éditions », ce bloc ne suit pas la jauge du haut, on le dit.
                Text(t("ios.releases.byPrint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(detail.rarities) { row in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack {
                            Text(row.rarity).lineLimit(1)
                            Spacer()
                            Text("\(row.ownedPrints)/\(row.prints)").monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Meter(value: row.ownedPrints, total: row.prints, height: 4)
                    }
                }
            }
        }
    }

    /// Les trois états d'une vignette. Au doigt il n'y a pas de survol : si ça n'est pas
    /// écrit, ça n'existe pas.
    private var legend: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            legendRow(Pill(text: "×2", tint: Theme.success), t("ios.releases.legend.owned"))
            legendRow(Pill(text: t("releases.elsewhere"), tint: Theme.warning), t("ios.releases.legend.elsewhere"))
            legendRow(Pill(text: "—"), t("ios.releases.legend.missing"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileSurface()
    }

    private func legendRow(_ pill: Pill, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            pill.frame(width: 44, alignment: .leading)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Filtres et grille

    private func filters(_ detail: ReleaseDetail) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Picker(t("ios.releases.shownLabel"), selection: $shown) {
                ForEach(Shown.allCases, id: \.self) { value in
                    Text(t("releases.shown.\(value.rawValue)")).tag(value)
                }
            }
            .pickerStyle(.segmented)

            FilterBar {
                if detail.rarities.count > 1 {
                    FacetMenu(
                        allLabel: t("releases.filters.allRarities"),
                        options: detail.rarities.map {
                            FacetValue(value: $0.rarity, count: $0.prints, label: nil)
                        },
                        selection: $rarity)
                }
                FilterChip(
                    t("releases.anyEdition"), isOn: anyEdition, action: { anyEdition.toggle() })
            }
        }
    }

    @ViewBuilder
    private func grid(_ detail: ReleaseDetail) -> some View {
        let cards = detail.cards.filter { card in
            (rarity == nil || card.rarity == rarity)
                && (shown == .all
                    || (shown == .owned ? card.isOwned(anyEdition: anyEdition)
                        : !card.isOwned(anyEdition: anyEdition)))
        }
        if cards.isEmpty {
            Text(t("releases.noCardsShown"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: GridWidth.card), spacing: Spacing.s)],
                spacing: Spacing.m
            ) {
                ForEach(cards) { card in
                    Button { selected = CardLink(cardId: card.card.id) } label: {
                        PrintTile(card: card, anyEdition: anyEdition)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PrintTile: View {
    let card: ReleaseCard
    let anyEdition: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            CardArt(card: card.card, dimmed: !card.isOwned(anyEdition: anyEdition))
                .overlay(alignment: .topTrailing) { badge }
            Text(card.printCode)
                .font(.system(size: 9, weight: .medium).monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(card.rarity)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            card.owned > 0
                ? t("ios.releases.legend.owned")
                : card.ownedElsewhere > 0 ? t("ios.releases.legend.elsewhere")
                : t("ios.releases.legend.missing"))
    }

    @ViewBuilder
    private var badge: some View {
        if card.owned > 0 {
            Pill(text: "×\(card.owned)", tint: Theme.success).padding(3)
        } else if card.ownedElsewhere > 0 {
            // Possédée, mais pas dans cette extension : utile à savoir avant de racheter
            Pill(text: t("releases.elsewhere"), tint: Theme.warning).padding(3)
        }
    }
}
