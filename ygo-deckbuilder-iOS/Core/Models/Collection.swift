import Foundation

nonisolated enum CollectionSort: String, Hashable, Sendable, CaseIterable, Identifiable {
    case name, quantity, value, rarity, newest
    var id: String { rawValue }
}

/// Filtres de l'onglet Cartes : les facettes se cumulent, les étiquettes aussi.
nonisolated struct CollectionQuery: Hashable, Sendable {
    var q: String = ""
    var category: CardCategory?
    var archetype: String?
    var rarity: String?
    var language: CardLanguage?
    var condition: CardCondition?
    var setId: String?
    var firstEdition = false
    var tagIds: [String] = []
    var sort: CollectionSort = .name
    var page: Int = 1
    var pageSize: Int = 40

    var items: [URLQueryItem] {
        var out: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "pageSize", value: String(pageSize)),
            .init(name: "sort", value: sort.rawValue),
        ]
        let text = q.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { out.append(.init(name: "q", value: text)) }
        if let category { out.append(.init(name: "category", value: category.rawValue)) }
        if let archetype { out.append(.init(name: "archetype", value: archetype)) }
        if let rarity { out.append(.init(name: "rarity", value: rarity)) }
        if let language { out.append(.init(name: "language", value: language.rawValue)) }
        if let condition { out.append(.init(name: "condition", value: condition.rawValue)) }
        if let setId { out.append(.init(name: "setId", value: setId)) }
        if firstEdition { out.append(.init(name: "firstEdition", value: "true")) }
        if !tagIds.isEmpty { out.append(.init(name: "tagIds", value: tagIds.joined(separator: ","))) }
        return out
    }

    /// Un filtre est-il posé, en dehors de la pagination et du tri ?
    var isFiltering: Bool {
        !q.trimmingCharacters(in: .whitespaces).isEmpty || category != nil || archetype != nil
            || rarity != nil || language != nil || condition != nil || setId != nil
            || firstEdition || !tagIds.isEmpty
    }
}

/// Filtres de l'onglet Produits.
nonisolated struct OwnedProductsQuery: Hashable, Sendable {
    nonisolated enum Sort: String, Hashable, Sendable, CaseIterable, Identifiable {
        case added, name, date, completeness
        var id: String { rawValue }
    }

    var q: String = ""
    var kind: ProductKind?
    var tagIds: [String] = []
    var complete = false
    var sort: Sort = .added

    var items: [URLQueryItem] {
        var out: [URLQueryItem] = [.init(name: "sort", value: sort.rawValue)]
        let text = q.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { out.append(.init(name: "q", value: text)) }
        if let kind { out.append(.init(name: "kind", value: kind.rawValue)) }
        if complete { out.append(.init(name: "complete", value: "true")) }
        if !tagIds.isEmpty { out.append(.init(name: "tagIds", value: tagIds.joined(separator: ","))) }
        return out
    }

    var isFiltering: Bool {
        !q.trimmingCharacters(in: .whitespaces).isEmpty || kind != nil || complete || !tagIds.isEmpty
    }
}

/// Impression rattachée à une ligne de collection ou de wishlist.
nonisolated struct PrintRef: Codable, Hashable, Sendable {
    let id: String
    let printCode: String
    let rarity: String
    let setName: String
    let price: Double?
}

nonisolated struct CollectionItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let quantity: Int
    let condition: String
    let language: String
    let firstEdition: Bool
    let notes: String?
    let card: CardSummary
    let print: PrintRef?
}

/// Valeurs de filtre réellement présentes dans la collection, avec leur effectif.
nonisolated struct CollectionFacets: Decodable, Sendable {
    let categories: [FacetValue]
    let archetypes: [FacetValue]
    let rarities: [FacetValue]
    let languages: [FacetValue]
    let conditions: [FacetValue]
    /// La valeur est l'identifiant de l'extension, son nom est dans le libellé.
    let sets: [FacetValue]
}

nonisolated struct CollectionStats: Codable, Hashable, Sendable {
    let totalCopies: Int
    let distinctCards: Int
    let estimatedValue: Double
}

nonisolated struct AddCollectionItemBody: Encodable, Sendable {
    let cardId: Int
    var printId: String?
    var quantity: Int = 1
    var condition: CardCondition = .nearMint
    var language: CardLanguage
    var firstEdition: Bool = false
}

nonisolated struct UpdateCollectionItemBody: Encodable, Sendable {
    var quantity: Int?
}

nonisolated struct ImportSetBody: Encodable, Sendable {
    let setName: String
    var copies: Int = 1
    var language: CardLanguage
}

nonisolated struct ImportSetResult: Decodable, Sendable {
    let productId: String
    let set: String
    let cardsAdded: Int
    let copiesAdded: Int
    let quantitiesVerified: Bool
}

// MARK: - Produits possédés

nonisolated struct OwnedProduct: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let set: CardSet
    let copies: Int
    let language: CardLanguage
    let addedAt: String
    let totalCards: Int
    let distinctCards: Int
    let quantitiesVerified: Bool
    /// 0...1
    let completeness: Double
    let missingCopies: Int
    let isDeck: Bool
    /// Étiquettes personnelles posées sur l'extension de ce produit. Optionnel : une app
    /// plus récente que son serveur doit continuer à lire la liste des produits.
    let tagIds: [String]?

    var tags: [String] { tagIds ?? [] }
}

nonisolated struct OwnedProductCard: Decodable, Hashable, Sendable {
    let card: CardSummary
    let printCode: String
    let rarity: String
    let quantity: Int
    let needed: Int
    let owned: Int
    /// MAIN ou EXTRA
    let zone: DeckZone
}

nonisolated struct OwnedProductDetail: Decodable, Sendable, Identifiable {
    let id: String
    let set: CardSet
    let copies: Int
    let language: CardLanguage
    let addedAt: String
    let totalCards: Int
    let distinctCards: Int
    let quantitiesVerified: Bool
    let completeness: Double
    let missingCopies: Int
    let isDeck: Bool
    let tagIds: [String]?
    let cards: [OwnedProductCard]

    var tags: [String] { tagIds ?? [] }
}

// MARK: - Wishlist

nonisolated struct WishlistItem: Decodable, Hashable, Sendable, Identifiable {
    nonisolated struct DeckRef: Decodable, Hashable, Sendable {
        let id: String
        let name: String
    }

    let id: String
    let quantity: Int
    let priority: WishlistPriority
    let language: String?
    let maxPrice: Double?
    let notes: String?
    let card: CardSummary
    let print: PrintRef?
    let deck: DeckRef?
    let unitPrice: Double?
}

nonisolated struct Wishlist: Decodable, Sendable {
    let items: [WishlistItem]
    let totalEstimated: Double
}

nonisolated struct AddWishlistBody: Encodable, Sendable {
    let cardId: Int
    var printId: String?
    var deckId: String?
    var quantity: Int = 1
    var maxPrice: Double?
    var priority: WishlistPriority?
}

nonisolated struct UpdateWishlistBody: Encodable, Sendable {
    var priority: WishlistPriority?
    var quantity: Int?
}
