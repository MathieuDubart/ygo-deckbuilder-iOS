import Foundation

/// Suivi par extension (cf. packages/shared/src/schemas/releases.ts).

nonisolated enum ReleaseStatus: String, Decodable, Hashable, Sendable, CaseIterable {
    case upcoming = "UPCOMING", recent = "RECENT", released = "RELEASED"
}

nonisolated enum ReleaseProgressFilter: String, Hashable, Sendable, CaseIterable {
    case none = "NONE", started = "STARTED", complete = "COMPLETE"
}

nonisolated enum ReleaseSort: String, Hashable, Sendable, CaseIterable {
    case date, progress, name, cards
}

/// Avancement sous ses deux lectures : l'impression exacte (vue collectionneur) et la carte
/// quelle que soit son édition (vue joueur). L'interface choisit laquelle montrer.
nonisolated struct ReleaseProgress: Decodable, Hashable, Sendable {
    let prints: Int
    let cards: Int
    let ownedPrints: Int
    let ownedCards: Int
    let copies: Int

    func owned(anyEdition: Bool) -> Int { anyEdition ? ownedCards : ownedPrints }
    func total(anyEdition: Bool) -> Int { anyEdition ? cards : prints }

    /// 0…1 ; 0 quand la liste de l'extension n'est pas encore connue.
    func ratio(anyEdition: Bool) -> Double {
        let total = total(anyEdition: anyEdition)
        guard total > 0 else { return 0 }
        return min(1, Double(owned(anyEdition: anyEdition)) / Double(total))
    }
}

nonisolated struct Release: Decodable, Hashable, Sendable, Identifiable {
    let set: CardSet
    let status: ReleaseStatus
    /// Jours avant la sortie (statut `upcoming`), sinon nil.
    let daysUntil: Int?
    let progress: ReleaseProgress
    let ownedProduct: Bool
    let ownedValue: Double
    let missingValue: Double
    /// Optionnel comme ailleurs : une app plus récente que son serveur doit continuer à lire.
    let tagIds: [String]?

    // `self.` obligatoire : dans le corps d'une propriété calculée, `set` seul est lu comme
    // le mot-clé d'un accesseur en écriture.
    var id: String { self.set.id }
    var tags: [String] { tagIds ?? [] }
    /// Extension annoncée dont aucune carte n'est connue.
    var unrevealed: Bool { progress.prints == 0 }
}

/// Une impression à tirer dans l'extension, et où on en est dessus.
nonisolated struct ReleaseCard: Decodable, Hashable, Sendable, Identifiable {
    let card: CardSummary
    let printId: String
    let printCode: String
    let rarity: String
    let rarityCode: String?
    let price: Double?
    /// Exemplaires de cette impression précise.
    let owned: Int
    /// Exemplaires de la même carte venus d'une autre impression.
    let ownedElsewhere: Int

    var id: String { printId }

    /// Compte-t-elle comme tirée ? Avec « toutes éditions », la posséder ailleurs suffit.
    func isOwned(anyEdition: Bool) -> Bool {
        owned > 0 || (anyEdition && ownedElsewhere > 0)
    }
}

nonisolated struct ReleaseRarity: Decodable, Hashable, Sendable, Identifiable {
    let rarity: String
    let prints: Int
    let ownedPrints: Int

    var id: String { rarity }
}

nonisolated struct ReleaseDetail: Decodable, Sendable {
    let set: CardSet
    let status: ReleaseStatus
    let daysUntil: Int?
    let progress: ReleaseProgress
    let ownedProduct: Bool
    let ownedValue: Double
    let missingValue: Double
    let tagIds: [String]?
    let cards: [ReleaseCard]
    let rarities: [ReleaseRarity]

    var tags: [String] { tagIds ?? [] }
    var unrevealed: Bool { progress.prints == 0 }
}

/// Ce qu'on met en avant : ce qui arrive, et ce qui vient de sortir.
nonisolated struct ReleaseSpotlight: Decodable, Sendable {
    let upcoming: [Release]
    let recent: [Release]
}

nonisolated struct FacetValue: Decodable, Hashable, Sendable, Identifiable {
    let value: String
    let count: Int
    /// Libellé lisible quand la valeur n'en est pas un (nom d'une extension).
    let label: String?

    var id: String { value }
    var display: String { label ?? value }
}

nonisolated struct ReleaseFacets: Decodable, Sendable {
    let kinds: [FacetValue]
    let statuses: [FacetValue]
    let years: [FacetValue]
}

nonisolated struct ReleaseQuery: Hashable, Sendable {
    var q: String = ""
    var kind: ProductKind?
    var status: ReleaseStatus?
    var progress: ReleaseProgressFilter?
    var year: Int?
    var tagIds: [String] = []
    var ownedProduct = false
    var sort: ReleaseSort = .date
    var page: Int = 1
    var pageSize: Int = 24

    var items: [URLQueryItem] {
        var out: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "pageSize", value: String(pageSize)),
            .init(name: "sort", value: sort.rawValue),
        ]
        let text = q.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { out.append(.init(name: "q", value: text)) }
        if let kind { out.append(.init(name: "kind", value: kind.rawValue)) }
        if let status { out.append(.init(name: "status", value: status.rawValue)) }
        if let progress { out.append(.init(name: "progress", value: progress.rawValue)) }
        if let year { out.append(.init(name: "year", value: String(year))) }
        if ownedProduct { out.append(.init(name: "ownedProduct", value: "true")) }
        // Les étiquettes voyagent en liste séparée par des virgules
        if !tagIds.isEmpty { out.append(.init(name: "tagIds", value: tagIds.joined(separator: ","))) }
        return out
    }

    /// Un filtre est-il posé, en dehors de la pagination et du tri ?
    var isFiltering: Bool {
        !q.trimmingCharacters(in: .whitespaces).isEmpty || kind != nil || status != nil
            || progress != nil || year != nil || ownedProduct || !tagIds.isEmpty
    }
}
