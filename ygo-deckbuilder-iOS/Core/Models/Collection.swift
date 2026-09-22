import Foundation

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
    let cards: [OwnedProductCard]
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
