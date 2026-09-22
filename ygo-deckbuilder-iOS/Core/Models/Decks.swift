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

    var coverURL: URL? { coverImageUrl.flatMap(URL.init(string:)) }
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
