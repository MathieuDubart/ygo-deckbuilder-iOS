import Foundation

nonisolated struct DeckCardEntry: Codable, Hashable, Sendable {
    let cardId: Int
    let zone: DeckZone
    let quantity: Int
}

nonisolated struct DeckCard: Decodable, Hashable, Sendable {
    let cardId: Int
    let zone: DeckZone
    let quantity: Int
    let ownedQuantity: Int
    let card: CardSummary
}

/// Problème de légalité (cf. validateDeck dans packages/shared).
nonisolated struct DeckIssue: Codable, Hashable, Sendable {
    nonisolated enum Code: String, Codable, Sendable {
        case zoneTooSmall = "ZONE_TOO_SMALL"
        case zoneTooLarge = "ZONE_TOO_LARGE"
        case forbidden = "FORBIDDEN"
        case tooManyCopies = "TOO_MANY_COPIES"
        case wrongZone = "WRONG_ZONE"
    }

    let code: Code
    var zone: DeckZone?
    var cardId: Int?
    var count: Int?
    var limit: Int?
}

nonisolated struct Deck: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let format: DeckFormat
    let isPublic: Bool
    let createdAt: String
    let updatedAt: String
    let cards: [DeckCard]
    let issues: [DeckIssue]
}

nonisolated struct DeckListItem: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let format: DeckFormat
    let updatedAt: String
    let mainCount: Int
    let extraCount: Int
    let sideCount: Int
    let coverImageUrl: String?
    /// Étiquettes posées dessus. Serveur antérieur : la clé est absente, pas vide.
    let tagIds: [String]?
    /// Monté depuis la liste officielle d'un produit, et non écrit à la main.
    let fromProduct: Bool?
    /// Solidité 0..100, la même note que les decks suggérés. Null = trop incomplet pour juger.
    let strength: Int?
    /// Brut, et relu après coup : une forme ajoutée côté serveur ne doit pas faire échouer
    /// le décodage de TOUTE la liste. Un enum strict le ferait, et l'onglet entier
    /// deviendrait un écran d'erreur pour un mot inconnu.
    private let styleRaw: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, format, updatedAt, mainCount, extraCount, sideCount
        case coverImageUrl, tagIds, fromProduct, strength
        case styleRaw = "style"
    }

    var coverURL: URL? { coverImageUrl.flatMap(URL.init(string:)) }
    var tags: [String] { tagIds ?? [] }
    var isFromProduct: Bool { fromProduct ?? false }
    var style: DeckStyle? { styleRaw.flatMap(DeckStyle.init(rawValue:)) }
}

/**
 Les cinq formes de jeu. Un deck n'est pas « fort » dans l'absolu : il l'est contre
 certaines formes et pas contre d'autres, et c'est ce que les pronostics disent.
 */
nonisolated enum DeckStyle: String, Decodable, Hashable, Sendable, CaseIterable, Identifiable {
    case combo = "COMBO"
    case midrange = "MIDRANGE"
    case control = "CONTROL"
    case stun = "STUN"
    case beatdown = "BEATDOWN"

    var id: String { rawValue }
}

nonisolated enum MatchupVerdict: String, Decodable, Hashable, Sendable {
    case good = "GOOD"
    case even = "EVEN"
    case bad = "BAD"
}

nonisolated struct Matchup: Decodable, Hashable, Sendable {
    /// Le style affronté.
    let against: DeckStyle
    /// Nom du deck du meta quand le pronostic vise un adversaire réel.
    let opponent: String?
    let verdict: MatchupVerdict
    /// Clé de la cause : le texte vit dans les paquets de messages.
    let reason: String
}

/// Ce qu'un deck sait faire. Le serveur en dit davantage — sept axes — mais on ne décode
/// que ce qu'on affiche : un champ qu'aucune vue ne lit n'est qu'une raison d'échouer.
nonisolated struct DeckProfile: Decodable, Hashable, Sendable {
    let style: DeckStyle
}

/// Force d'un deck : sa note, sa forme, et contre quoi elle vaut.
nonisolated struct DeckStrength: Decodable, Hashable, Sendable {
    let score: DeckScore
    let profile: DeckProfile
    /// Du plus favorable au moins favorable.
    let matchups: [Matchup]
}

/// Filtres de « Mes decks ». Mêmes outils que la collection : recherche, étiquettes
/// cumulées (ET, pas OU) et tri.
nonisolated struct DecksQuery: Hashable, Sendable {
    nonisolated enum Sort: String, Hashable, Sendable, CaseIterable, Identifiable {
        case updated, created, name, size, strength
        var id: String { rawValue }
    }

    var q: String = ""
    var tagIds: [String] = []
    var format: DeckFormat?
    var sort: Sort = .updated

    var items: [URLQueryItem] {
        var out: [URLQueryItem] = [.init(name: "sort", value: sort.rawValue)]
        let text = q.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { out.append(.init(name: "q", value: text)) }
        if let format { out.append(.init(name: "format", value: format.rawValue)) }
        if !tagIds.isEmpty { out.append(.init(name: "tagIds", value: tagIds.joined(separator: ","))) }
        return out
    }

    var isFiltering: Bool {
        !q.trimmingCharacters(in: .whitespaces).isEmpty || format != nil || !tagIds.isEmpty
    }
}

nonisolated struct CreateDeckBody: Encodable, Sendable {
    let name: String
    var format: DeckFormat = .tcg
    var cards: [DeckCardEntry] = []
}

/// PATCH /decks/:id — champs optionnels (les nil ne sont pas envoyés).
nonisolated struct UpdateDeckBody: Encodable, Sendable {
    var name: String?
    var format: DeckFormat?
    var cards: [DeckCardEntry]?
}

nonisolated struct ImportYdkBody: Encodable, Sendable {
    let name: String
    var format: DeckFormat = .tcg
    let content: String
}

nonisolated struct CardSuggestion: Decodable, Hashable, Sendable {
    nonisolated enum Reason: String, Decodable, Sendable {
        case sameArchetype = "SAME_ARCHETYPE", mentioned = "MENTIONED_IN_TEXT", staple = "STAPLE"
    }

    let card: CardSummary
    let reason: Reason
    let ownedQuantity: Int
}

/**
 État de la banlist locale. `changed` dit si la dernière relecture a bougé un statut : c'est le
 seul signal dont le client a besoin pour décider de recharger un deck ou pas.
 */
nonisolated struct BanlistStatus: Codable, Hashable, Sendable {
    let changed: Bool
    /// Dernière relecture, ou nil si la banlist n'a jamais été lue avec succès.
    let checkedAt: String?
    let listed: Int
}
