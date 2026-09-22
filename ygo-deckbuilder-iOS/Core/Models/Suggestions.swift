import Foundation

nonisolated struct MissingCard: Decodable, Hashable, Sendable {
    let card: CardSummary
    let zone: DeckZone
    let required: Int
    let owned: Int
    let missing: Int
    let unitPrice: Double?
}

nonisolated struct MetaDeckSuggestion: Decodable, Hashable, Sendable, Identifiable {
    let metaDeckId: String
    let name: String
    let archetype: String?
    let tier: Int?
    let source: String?
    let listCount: Int
    let share: Double?
    let variants: [String]
    let coverImageUrl: String?
    let coverage: Double
    let ownedCopies: Int
    let requiredCopies: Int
    let missing: [MissingCard]
    let estimatedCostToComplete: Double

    var id: String { metaDeckId }
    var coverURL: URL? { coverImageUrl.flatMap(URL.init(string:)) }
}

nonisolated struct ArchetypeSuggestion: Decodable, Hashable, Sendable, Identifiable {
    let archetype: String
    let distinctCards: Int
    let totalCopies: Int
    var id: String { archetype }
}

nonisolated struct OfficialDeckSuggestion: Decodable, Hashable, Sendable, Identifiable {
    let productDeckId: String
    let deckName: String?
    let kind: OfficialDeckKind
    let product: CardSet
    let archetype: String?
    let coverage: Double
    let ownedCopies: Int
    let requiredCopies: Int
    let estimatedCostToComplete: Double
    let productOwned: Bool

    var id: String { productDeckId }
    /// « Produit — Deck » pour les coffrets, sinon le nom du produit.
    var displayName: String { deckName.map { "\(product.name) — \($0)" } ?? product.name }
}

/// Note de solidité d'un deck généré.
nonisolated struct DeckScore: Decodable, Hashable, Sendable {
    let score: Int
    let engineShare: Double
    let staples: Int
    let consistency: Double
    let fillerShare: Double
    let metaCoverage: Double?
    let synergy: Double?
    let starters: Int?
    let playable: Bool
}

nonisolated struct ZoneCounts: Decodable, Hashable, Sendable {
    let MAIN: Int
    let EXTRA: Int
    let SIDE: Int

    subscript(zone: DeckZone) -> Int {
        switch zone {
        case .main: MAIN
        case .extra: EXTRA
        case .side: SIDE
        }
    }
}

/// Ce qu'on veut générer (cf. GenerationTarget côté web).
nonisolated enum GenerationTarget: Hashable, Sendable, Identifiable, Decodable {
    case meta(metaDeckId: String, name: String)
    case official(productDeckId: String, name: String)
    case archetype(String)

    var id: String {
        switch self {
        case .meta(let id, _): "meta-\(id)"
        case .official(let id, _): "official-\(id)"
        case .archetype(let a): "archetype-\(a)"
        }
    }

    /// Les decks meta et officiels existent en deux versions (liste complète / avec mes cartes).
    var hasModes: Bool {
        if case .archetype = self { return false }
        return true
    }

    private enum CodingKeys: String, CodingKey { case kind, metaDeckId, productDeckId, name, archetype }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "meta":
            self = .meta(
                metaDeckId: try c.decode(String.self, forKey: .metaDeckId),
                name: try c.decode(String.self, forKey: .name))
        case "official":
            self = .official(
                productDeckId: try c.decode(String.self, forKey: .productDeckId),
                name: try c.decode(String.self, forKey: .name))
        default:
            self = .archetype(try c.decode(String.self, forKey: .archetype))
        }
    }
}

nonisolated struct PlayableDeck: Decodable, Hashable, Sendable {
    let target: GenerationTarget
    let name: String
    let archetype: String?
    let tier: Int?
    let score: DeckScore
    let counts: ZoneCounts
    let highlights: [CardSummary]
}

nonisolated struct GeneratedDeckCard: Decodable, Hashable, Sendable {
    let card: CardSummary
    let zone: DeckZone
    let quantity: Int
    let owned: Int
    let source: GeneratedCardSource
    let inclusion: Double?

    var missing: Int { max(0, quantity - owned) }
}

nonisolated struct GeneratedDeck: Decodable, Sendable {
    let name: String
    /// OWNED, META ou ARCHETYPE
    let mode: String
    let metaDeckId: String?
    let archetype: String?
    let cards: [GeneratedDeckCard]
    let counts: ZoneCounts
    let missingCopies: Int
    let missingCost: Double
    let complete: Bool
    let score: DeckScore
    let notes: [String]
}
