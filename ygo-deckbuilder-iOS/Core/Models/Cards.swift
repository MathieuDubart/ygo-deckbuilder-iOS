import Foundation

nonisolated struct Paginated<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
    let page: Int
    let pageSize: Int
    let total: Int
    let totalPages: Int
    /// Aucun résultat exact : résultats approchants (tolérance aux fautes).
    let approximate: Bool?
}

nonisolated struct CardSummary: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let category: CardCategory
    let type: String
    let frameType: String
    let archetype: String?
    let attribute: String?
    let race: String?
    let level: Int?
    let atk: Int?
    let def: Int?
    let imageUrl: String?
    let imageUrlSmall: String?
    let isExtraDeck: Bool
    let banTcg: String?
    let priceCardmarket: Double?
    let ownedQuantity: Int?

    var imageURL: URL? { (imageUrl ?? imageUrlSmall).flatMap(URL.init(string:)) }
    var owned: Int { ownedQuantity ?? 0 }
    var isMonster: Bool { category == .monster }
}

nonisolated struct CardPrint: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let setCode: String?
    let setName: String
    let printCode: String
    let rarity: String
    let rarityCode: String?
    let price: Double?
}

nonisolated struct CardDetail: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let category: CardCategory
    let type: String
    let frameType: String
    let archetype: String?
    let attribute: String?
    let race: String?
    let level: Int?
    let atk: Int?
    let def: Int?
    let imageUrl: String?
    let imageUrlSmall: String?
    let isExtraDeck: Bool
    let banTcg: String?
    let priceCardmarket: Double?
    let ownedQuantity: Int?
    let desc: String
    let linkVal: Int?
    let linkMarkers: [String]
    let scale: Int?
    let banOcg: String?
    let prints: [CardPrint]

    var imageURL: URL? { (imageUrl ?? imageUrlSmall).flatMap(URL.init(string:)) }

    /// Résumé (pour le deck builder, qui manipule des CardSummary).
    var summary: CardSummary {
        CardSummary(
            id: id, name: name, category: category, type: type, frameType: frameType,
            archetype: archetype, attribute: attribute, race: race, level: level, atk: atk,
            def: def, imageUrl: imageUrl, imageUrlSmall: imageUrlSmall, isExtraDeck: isExtraDeck,
            banTcg: banTcg, priceCardmarket: priceCardmarket, ownedQuantity: ownedQuantity
        )
    }
}

nonisolated struct CardSet: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let code: String?
    let tcgDate: String?
    let kind: ProductKind
    let imageUrl: String?
    let fallbackImageUrl: String?
    let cardCount: Int

    var imageURL: URL? { imageUrl.flatMap(URL.init(string:)) }
    var fallbackImageURL: URL? { fallbackImageUrl.flatMap(URL.init(string:)) }
}

nonisolated enum CardSort: String, Hashable, Sendable, CaseIterable, Identifiable {
    case relevance, name, newest, atk, def, level
    var id: String { rawValue }
}

/// Paramètres de GET /cards (cf. cardSearchSchema).
nonisolated struct CardSearchQuery: Hashable, Sendable {
    var q: String = ""
    var category: CardCategory?
    var archetype: String?
    var owned: Bool = false
    var sort: CardSort?
    var page: Int = 1
    var pageSize: Int = 36

    var items: [URLQueryItem] {
        var out: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "pageSize", value: String(pageSize)),
        ]
        let text = q.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { out.append(.init(name: "q", value: text)) }
        if let category { out.append(.init(name: "category", value: category.rawValue)) }
        if let archetype { out.append(.init(name: "archetype", value: archetype)) }
        if owned { out.append(.init(name: "owned", value: "true")) }
        if let sort { out.append(.init(name: "sort", value: sort.rawValue)) }
        return out
    }
}

// MARK: - Interactions

nonisolated struct CardInteractionGroup: Decodable, Hashable, Sendable {
    nonisolated enum Direction: String, Decodable, Sendable { case out = "OUT", `in` = "IN" }
    nonisolated enum Precision: String, Decodable, Sendable { case direct = "DIRECT", precise = "PRECISE" }

    let direction: Direction
    let verb: InteractionVerb
    let target: String?
    let precision: Precision
    let cards: [CardSummary]
    let total: Int
}

nonisolated struct CardInteractions: Decodable, Sendable {
    nonisolated struct Generic: Decodable, Hashable, Sendable {
        let verb: InteractionVerb
        let target: String
    }

    let cardId: Int
    let groups: [CardInteractionGroup]
    let generic: [Generic]
    let ownedLinked: Int
    let indexed: Bool
}
