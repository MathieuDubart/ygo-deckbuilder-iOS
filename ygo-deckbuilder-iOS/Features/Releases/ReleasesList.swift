import SwiftUI

struct ReleaseRoute: Hashable { let setId: String }

/// Onglet Extensions : ce qui arrive et ce qui vient de sortir en haut, puis toutes les
/// extensions du catalogue avec leur avancement. L'avancement se lit de deux façons —
/// l'impression exacte, ou la carte quelle que soit son édition — et la bascule
/// « toutes éditions » choisit laquelle compte, ici comme dans la fiche.
struct ReleasesList<Header: View>: View {
    let header: Header
    @Binding var anyEdition: Bool
    @Binding var refreshToken: Int

    @Environment(AppState.self) private var app
    @State private var query = ReleaseQuery()
    @State private var items: [Release] = []
    /// Hors de `query` : la pagination ne doit pas relancer le chargement des filtres.
    @State private var page = 1
    @State private var wantsMore = false
    @State private var total = 0
    @State private var totalPages = 1
    @State private var spotlight: ReleaseSpotlight?
    /// Avancement des amis sur la page affichée : une requête, pas une par ligne.
    @State private var friends: FriendsProgress = [:]
    @State private var facets: ReleaseFacets?
    @State private var loading = false
    @State private var error: String?
    /// Dernier texte de recherche vu par la tâche de chargement (cf. `debounce`).
    @State private var typed = ""

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: 0, bottom: Spacing.s, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            if let spotlight, !query.isFiltering {
                spotlightSection(t("releases.spotlight.upcoming"), "calendar.badge.clock", spotlight.upcoming)
                spotlightSection(t("releases.spotlight.recent"), "sparkles", spotlight.recent)
            }

            Section {
                filters
                    .listRowInsets(EdgeInsets(top: 0, leading: Spacing.l, bottom: 0, trailing: Spacing.l))
                    .listRowBackground(Color.clear)
            }

            if let error, items.isEmpty {
                ContentUnavailableView(
                    t("common.status.error"), systemImage: "wifi.exclamationmark", description: Text(error))
                    .listRowBackground(Color.clear)
            } else if items.isEmpty && !loading {
                ContentUnavailableView(
                    t("releases.empty.title"), systemImage: "shippingbox",
                    description: Text(query.isFiltering ? t("releases.empty.description") : ""))
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(items) { release in
                    NavigationLink(value: ReleaseRoute(setId: release.set.id)) {
                        ReleaseRow(
                            release: release, anyEdition: anyEdition, friends: friends[release.set.id])
                    }
                    .onAppear {
                        if release.id == items.last?.id { wantsMore = true }
                    }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
            } header: {
                if total > 0 { Text(t("releases.count", ["count": total])) }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Spacing.l)
        .searchable(text: $query.q, prompt: t("releases.searchPlaceholder"))
        .task(id: Reload(query: query, version: app.collectionVersion)) {
            // Le dernier caractère effacé mérite le même délai que les autres : sinon
            // vider le champ part aussitôt, juste après la frappe précédente.
            let isTyping = query.q != typed
            typed = query.q
            if isTyping {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            await reload()
        }
        // La page suivante passe par un état, pas par une tâche détachée : elle est ainsi
        // annulée comme le reste quand les filtres changent.
        .task(id: PageRequest(key: reloadKey, wants: wantsMore, page: page)) {
            guard wantsMore else { return }
            await loadMore()
        }
        .task(id: app.collectionVersion) { spotlight = try? await app.api.releaseSpotlight() }
        // Les amis affichés suivent la page chargée et l'état des amitiés
        .task(id: FriendsKey(ids: items.map(\.id), version: app.socialVersion)) {
            friends = (try? await app.api.friendsProgress(setIds: items.map(\.id))) ?? [:]
        }
        .task(id: app.collectionVersion) { facets = try? await app.api.releaseFacets() }
        .refreshable {
            refreshToken += 1
            await reload()
            spotlight = try? await app.api.releaseSpotlight()
            facets = try? await app.api.releaseFacets()
        }
    }

    /// Ce qui doit relancer le chargement. La page n'en fait pas partie : la faire entrer
    /// dans l'identité de la tâche relancerait un rechargement à chaque page chargée, qui
    /// remettrait la liste à la page 1 — et la dernière ligne redevenue visible relancerait
    /// le tout, en boucle.
    private struct Reload: Equatable {
        let query: ReleaseQuery
        let version: Int

        init(query: ReleaseQuery, version: Int) {
            var identity = query
            identity.page = 1
            self.query = identity
            self.version = version
        }
    }

    private var reloadKey: Reload { Reload(query: query, version: app.collectionVersion) }

    private struct FriendsKey: Equatable {
        let ids: [String]
        let version: Int
    }

    /// La demande de page porte l'identité du rechargement : changer de filtre doit vraiment
    /// annuler la page en vol. Surtout, elle ne porte PAS `loading` : `loadMore` modifie
    /// `loading`, qui est lu par `body` — l'y mettre ferait changer l'identité au milieu du
    /// chargement, et la tâche s'annulerait elle-même avant d'avoir rien ramené.
    private struct PageRequest: Equatable {
        let key: Reload
        let wants: Bool
        let page: Int
    }

    // MARK: - Mise en avant

    @ViewBuilder
    private func spotlightSection(_ title: String, _ icon: String, _ releases: [Release]) -> some View {
        if !releases.isEmpty {
            Section {
                ForEach(releases) { release in
                    NavigationLink(value: ReleaseRoute(setId: release.set.id)) {
                        SpotlightRow(release: release, anyEdition: anyEdition)
                    }
                }
            } header: {
                Label(title, systemImage: icon)
            }
        }
    }

    // MARK: - Filtres

    private var filters: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            FilterBar {
                FacetMenu(
                    allLabel: t("releases.filters.allStatuses"),
                    options: facets?.statuses ?? [],
                    selection: Binding(
                        get: { query.status?.rawValue },
                        set: { query.status = $0.flatMap(ReleaseStatus.init(rawValue:)) })
                ) { t("releases.status.\($0.value)") }

                FacetMenu(
                    allLabel: t("releases.filters.allKinds"),
                    options: facets?.kinds ?? [],
                    selection: Binding(
                        get: { query.kind?.rawValue },
                        set: { query.kind = $0.flatMap(ProductKind.init(rawValue:)) })
                ) { t("products.kinds.\($0.value)") }

                FacetMenu(
                    allLabel: t("releases.filters.allYears"),
                    options: facets?.years ?? [],
                    selection: Binding(
                        get: { query.year.map(String.init) },
                        set: { query.year = $0.flatMap(Int.init) }))

                FacetMenu(
                    allLabel: t("releases.filters.allProgress"),
                    options: ReleaseProgressFilter.allCases.map { FacetValue(value: $0.rawValue, count: 0, label: nil) },
                    selection: Binding(
                        get: { query.progress?.rawValue },
                        set: { query.progress = $0.flatMap(ReleaseProgressFilter.init(rawValue:)) })
                ) { t("releases.progress.\($0.value)") }

                Menu {
                    Picker(t("releases.filters.sort"), selection: $query.sort) {
                        ForEach(ReleaseSort.allCases, id: \.self) { sort in
                            Text(t("releases.sort.\(sort.rawValue)")).tag(sort)
                        }
                    }
                } label: {
                    ChipLabel(isOn: query.sort != .date) {
                        Label(
                            t("releases.sort.option", ["label": t("releases.sort.\(query.sort.rawValue)")]),
                            systemImage: "arrow.up.arrow.down")
                    }
                }

                FilterChip(
                    t("releases.filters.ownedProduct"),
                    isOn: query.ownedProduct,
                    action: { query.ownedProduct.toggle() })

                FilterChip(
                    t("releases.anyEdition"),
                    isOn: anyEdition,
                    action: { anyEdition.toggle() })
            }

            FilterBar {
                TagFilterRow(selection: $query.tagIds) { $0.setCount }
            }
        }
    }

    // MARK: - Chargement

    private func reload() async {
        loading = true
        // Relâcher la demande de page ici, et pas seulement en cas de succès : une demande
        // armée pendant le rechargement resterait sinon coincée, sans rien pour la relancer.
        defer {
            loading = false
            wantsMore = false
        }
        do {
            var first = query
            first.page = 1
            let result = try await app.api.releases(first)
            items = result.items
            total = result.total
            totalPages = result.totalPages
            page = 1
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
            total = 0
        }
    }

    private func loadMore() async {
        // Ne pas consommer la demande ici : un rechargement en vol (une frappe) la ferait
        // disparaître sans charger, et la liste resterait bloquée sur sa page.
        guard page < totalPages, !loading else { return }
        defer { wantsMore = false }
        loading = true
        defer { loading = false }
        var next = query
        next.page = page + 1
        guard let result = try? await app.api.releases(next), !Task.isCancelled else { return }
        let known = Set(items.map(\.id))
        items += result.items.filter { !known.contains($0.id) }
        page = next.page
        totalPages = result.totalPages
    }
}

// MARK: - Lignes

private struct ReleaseRow: View {
    let release: Release
    let anyEdition: Bool
    let friends: [FriendSetProgress]?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            ProductCover(set: release.set, width: .thumb)
                .frame(width: 52, height: 66)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(release.set.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                FlowLayout(spacing: Spacing.xxs) {
                    if let code = release.set.code { Pill(text: code) }
                    ReleaseStatusPill(status: release.status, daysUntil: release.daysUntil)
                    if release.ownedProduct {
                        Pill(text: t("releases.sealed"), tint: Theme.success)
                    }
                    TagPills(tagIds: release.tags)
                }
                if release.unrevealed {
                    Text(t("releases.unrevealed"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressLine(progress: release.progress, anyEdition: anyEdition)
                    FriendProgressStrip(friends: friends, anyEdition: anyEdition)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

private struct SpotlightRow: View {
    let release: Release
    let anyEdition: Bool

    var body: some View {
        HStack(spacing: Spacing.m) {
            ProductCover(set: release.set, width: .thumb)
                .frame(width: 34, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(release.set.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(releaseDate(release)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: Spacing.xs)
            ReleaseStatusPill(status: release.status, daysUntil: release.daysUntil)
        }
    }

    private func releaseDate(_ release: Release) -> String {
        let date = release.set.tcgDate.map(L10n.shared.date) ?? t("releases.noDate")
        guard !release.unrevealed else { return date }
        return t("ios.releases.spotlightMeta", [
            "date": date,
            "owned": release.progress.owned(anyEdition: anyEdition),
            "total": release.progress.total(anyEdition: anyEdition),
        ])
    }
}

/// « À venir », « Nouveau », ou le décompte avant la sortie.
struct ReleaseStatusPill: View {
    let status: ReleaseStatus
    let daysUntil: Int?

    var body: some View {
        switch status {
        case .upcoming:
            Pill(
                text: (daysUntil ?? 0) <= 0
                    ? t("releases.today")
                    : t("releases.inDays", ["count": daysUntil ?? 0]),
                tint: .accentColor)
        case .recent:
            Pill(text: t("releases.status.\(status.rawValue)"), tint: Theme.warning)
        case .released:
            EmptyView()
        }
    }
}

/// « 12 / 100 » et sa jauge.
struct ProgressLine: View {
    let progress: ReleaseProgress
    let anyEdition: Bool

    var body: some View {
        let owned = progress.owned(anyEdition: anyEdition)
        let total = progress.total(anyEdition: anyEdition)
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                Text("\(owned) / \(total)")
                Spacer()
                Text(L10n.shared.percent(progress.ratio(anyEdition: anyEdition)))
                    .foregroundStyle(owned >= total && total > 0 ? Theme.success : .secondary)
            }
            .font(.caption.monospacedDigit())
            Meter(value: owned, total: total)
        }
    }
}
