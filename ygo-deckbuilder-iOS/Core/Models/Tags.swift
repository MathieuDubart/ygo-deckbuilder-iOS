import Foundation

/// Étiquettes personnelles : des mots qu'on colle soi-même sur une carte ou une extension
/// (« à vendre », « doublons »). Rien à voir avec les facettes de tri, qui se déduisent du
/// catalogue (cf. packages/shared/src/schemas/tags.ts).

nonisolated enum TagColor: String, Codable, Hashable, Sendable, CaseIterable {
    case slate, red, amber, green, teal, blue, violet, pink

    /// Valeur inconnue (étiquette créée par une version plus récente) : gris neutre.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TagColor(rawValue: raw) ?? .slate
    }
}

nonisolated struct Tag: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let color: TagColor
    /// Cartes portant cette étiquette.
    let cardCount: Int
    /// Extensions portant cette étiquette.
    let setCount: Int
    /// Decks portant cette étiquette. Serveur antérieur : la clé est absente.
    let deckCount: Int?

    var decks: Int { deckCount ?? 0 }
}

nonisolated struct CreateTagBody: Encodable, Sendable {
    let name: String
    var color: TagColor = .slate
}

nonisolated struct UpdateTagBody: Encodable, Sendable {
    var name: String?
    var color: TagColor?
}
