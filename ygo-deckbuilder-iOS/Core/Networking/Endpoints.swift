import Foundation

/// Toutes les routes de l'API (cf. apps/api/src/modules/*/…controller.ts).
extension APIClient {
    // MARK: Serveur

    /// Vérifie qu'une adresse répond bien comme une instance YGO Deck Builder (avant de l'adopter).
    func checkServer(_ server: URL) async throws {
        var request = URLRequest(url: server.appending(path: "api/health"))
        request.timeoutInterval = 15
        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let health = try? JSONDecoder().decode(HealthStatus.self, from: body),
              health.status == "ok"
        else { throw APIError(status: status, message: t("ios.server.notAnInstance")) }
    }

    // MARK: Compte

    func login(email: String, password: String) async throws -> PublicUser {
        try await signIn("auth/login", body: LoginBody(email: email.lowercased(), password: password))
    }

    func register(email: String, username: String, password: String) async throws -> PublicUser {
        try await signIn(
            "auth/register", body: RegisterBody(email: email.lowercased(), username: username, password: password))
    }

    func me() async throws -> PublicUser { try await get("auth/me") }

    // MARK: Catalogue

    func searchCards(_ query: CardSearchQuery) async throws -> Paginated<CardSummary> {
        try await get("cards", query: query.items)
    }

    func card(_ id: Int) async throws -> CardDetail { try await get("cards/\(id)") }

    func interactions(_ id: Int) async throws -> CardInteractions { try await get("cards/\(id)/interactions") }

    func archetypes() async throws -> [String] { try await get("cards/archetypes") }

    func sets(q: String? = nil, kind: ProductKind? = nil) async throws -> [CardSet] {
        var items: [URLQueryItem] = []
        if let q, !q.isEmpty { items.append(.init(name: "q", value: q)) }
        if let kind { items.append(.init(name: "kind", value: kind.rawValue)) }
        return try await get("cards/sets", query: items)
    }

    // MARK: Collection

    func collection(_ query: CollectionQuery) async throws -> Paginated<CollectionItem> {
        try await get("collection", query: query.items)
    }

    func collectionStats() async throws -> CollectionStats { try await get("collection/stats") }

    /// Valeurs de filtre présentes dans la collection, avec leur effectif.
    func collectionFacets() async throws -> CollectionFacets { try await get("collection/facets") }

    func addToCollection(_ body: AddCollectionItemBody) async throws {
        try await perform(.post, "collection", body: body)
    }

    /// Quantité 0 = ligne supprimée.
    func setCollectionQuantity(_ id: String, quantity: Int) async throws {
        try await perform(.patch, "collection/\(id)", body: UpdateCollectionItemBody(quantity: quantity))
    }

    func removeFromCollection(_ id: String) async throws {
        try await perform(.delete, "collection/\(id)")
    }

    func importSet(_ body: ImportSetBody) async throws -> ImportSetResult {
        try await send(.post, "collection/import-set", body: body)
    }

    func ownedProducts(_ query: OwnedProductsQuery = .init()) async throws -> [OwnedProduct] {
        try await get("collection/products", query: query.items)
    }

    func ownedProduct(_ id: String) async throws -> OwnedProductDetail { try await get("collection/products/\(id)") }

    func removeProduct(_ id: String, removeCards: Bool) async throws {
        try await perform(.delete, "collection/products/\(id)", query: [.init(name: "removeCards", value: String(removeCards))])
    }

    // MARK: Extensions

    func releases(_ query: ReleaseQuery) async throws -> Paginated<Release> {
        try await get("collection/releases", query: query.items)
    }

    /// Sorties à venir et sorties récentes, mises en avant en haut de l'onglet.
    func releaseSpotlight() async throws -> ReleaseSpotlight {
        try await get("collection/releases/spotlight")
    }

    func releaseFacets() async throws -> ReleaseFacets { try await get("collection/releases/facets") }

    func release(_ setId: String) async throws -> ReleaseDetail {
        try await get("collection/releases/\(setId)")
    }

    // MARK: Étiquettes

    func tags() async throws -> [Tag] { try await get("tags") }

    func createTag(_ body: CreateTagBody) async throws -> Tag { try await send(.post, "tags", body: body) }

    @discardableResult
    func updateTag(_ id: String, _ body: UpdateTagBody) async throws -> Tag {
        try await send(.patch, "tags/\(id)", body: body)
    }

    func deleteTag(_ id: String) async throws { try await perform(.delete, "tags/\(id)") }

    /// Pose (`on`) ou retire l'étiquette sur une carte.
    @discardableResult
    func tagCard(_ tagId: String, cardId: Int, on: Bool) async throws -> Tag {
        try await send(on ? .put : .delete, "tags/\(tagId)/cards/\(cardId)")
    }

    /// Pose ou retire l'étiquette sur une extension.
    @discardableResult
    func tagSet(_ tagId: String, setId: String, on: Bool) async throws -> Tag {
        try await send(on ? .put : .delete, "tags/\(tagId)/sets/\(setId)")
    }

    // MARK: Banlist

    /**
     Demande au serveur de relire la banlist si elle a vieilli. Le serveur borne la fréquence
     réelle par l'âge de la dernière lecture : on peut donc l'appeler à chaque ouverture de
     deck sans y penser.
     */
    func refreshBanlist() async throws -> BanlistStatus { try await send(.post, "banlist/refresh") }

    // MARK: Decks

    func decks() async throws -> [DeckListItem] { try await get("decks") }

    func deck(_ id: String) async throws -> Deck { try await get("decks/\(id)") }

    func createDeck(_ body: CreateDeckBody) async throws -> Deck { try await send(.post, "decks", body: body) }

    func importYdk(_ body: ImportYdkBody) async throws -> Deck { try await send(.post, "decks/import-ydk", body: body) }

    @discardableResult
    func updateDeck(_ id: String, _ body: UpdateDeckBody) async throws -> Deck {
        try await send(.patch, "decks/\(id)", body: body)
    }

    func duplicateDeck(_ id: String) async throws -> Deck { try await send(.post, "decks/\(id)/duplicate") }

    func deleteDeck(_ id: String) async throws { try await perform(.delete, "decks/\(id)") }

    func exportYdk(_ id: String) async throws -> String { try await text("decks/\(id)/export.ydk") }

    func deckCardSuggestions(_ id: String) async throws -> [CardSuggestion] {
        try await get("suggestions/decks/\(id)/cards")
    }

    // MARK: Wishlist

    func wishlist() async throws -> Wishlist { try await get("wishlist") }

    func addToWishlist(_ body: AddWishlistBody) async throws { try await perform(.post, "wishlist", body: body) }

    func updateWishlist(_ id: String, _ body: UpdateWishlistBody) async throws {
        try await perform(.patch, "wishlist/\(id)", body: body)
    }

    func markAcquired(_ id: String) async throws { try await perform(.post, "wishlist/\(id)/acquired") }

    func removeFromWishlist(_ id: String) async throws { try await perform(.delete, "wishlist/\(id)") }

    // MARK: Suggestions

    func metaSuggestions(limit: Int = 30) async throws -> [MetaDeckSuggestion] {
        try await get("suggestions/meta-decks", query: [.init(name: "limit", value: String(limit))])
    }

    func archetypeSuggestions() async throws -> [ArchetypeSuggestion] { try await get("suggestions/archetypes") }

    func playableDecks() async throws -> [PlayableDeck] { try await get("suggestions/playable") }

    func officialDecks(kind: OfficialDeckKind?, limit: Int = 60) async throws -> [OfficialDeckSuggestion] {
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let kind { items.append(.init(name: "kind", value: kind.rawValue)) }
        return try await get("suggestions/official-decks", query: items)
    }

    func generate(_ target: GenerationTarget, mode: GenerationMode) async throws -> GeneratedDeck {
        let modeItem = URLQueryItem(name: "mode", value: mode.rawValue)
        switch target {
        case .meta(let id, _):
            return try await get("suggestions/generate/meta/\(id)", query: [modeItem])
        case .official(let id, _):
            return try await get("suggestions/generate/official/\(id)", query: [modeItem])
        case .archetype(let archetype):
            return try await get("suggestions/generate/archetype", query: [.init(name: "archetype", value: archetype)])
        }
    }

    func guide(_ request: DeckGuideRequest) async throws -> DeckGuide {
        try await send(.post, "suggestions/guide", body: request)
    }

    /// null tant que la meta n'a jamais été calculée.
    func metaStatus() async throws -> SyncStatus? {
        let body = try await self.data(.get, "meta-decks/status")
        return try? JSONDecoder().decode(SyncStatus.self, from: body)
    }

    func syncMeta() async throws -> MetaSyncResult { try await send(.post, "meta-decks/sync") }

    // MARK: Profils et amis

    func myProfile() async throws -> ProfileView { try await get("me/profile") }

    func profile(of username: String) async throws -> ProfileView {
        try await get("users/\(encoded(username))/profile")
    }

    func updateUsername(_ username: String) async throws {
        try await perform(.patch, "me/profile", body: UpdateProfileBody(username: username))
    }

    func setProfileCards(_ printIds: [String]) async throws -> [ProfileCard] {
        try await send(.put, "me/profile/cards", body: ProfileCardsBody(printIds: printIds))
    }

    /// `kind` vaut "avatar" ou "banner". L'image part telle quelle : le serveur la réencode.
    func uploadProfileImage(_ kind: String, data: Data, mimeType: String) async throws -> UploadedImage {
        try await upload("me/profile/\(kind)", fileName: "image", mimeType: mimeType, data: data)
    }

    func removeProfileImage(_ kind: String) async throws {
        try await perform(.delete, "me/profile/\(kind)")
    }

    func searchUsers(_ query: String) async throws -> [UserSearchResult] {
        try await get("users/search", query: [.init(name: "q", value: query)])
    }

    func friends() async throws -> [Friend] { try await get("friends") }

    func friendRequests() async throws -> [FriendRequest] { try await get("friends/requests") }

    func requestFriend(username: String) async throws -> UserSearchResult {
        try await send(.post, "friends/requests", body: FriendRequestBody(username: username))
    }

    func respondToRequest(_ id: String, accept: Bool) async throws {
        try await perform(.post, "friends/requests/\(id)/\(accept ? "accept" : "decline")")
    }

    /// Retire l'ami ou annule la demande envoyée : c'est le même geste.
    func removeFriend(_ userId: String) async throws {
        try await perform(.delete, "friends/\(userId)")
    }

    /// Avancement des amis sur les extensions affichées : une requête pour toute la page.
    func friendsProgress(setIds: [String]) async throws -> FriendsProgress {
        guard !setIds.isEmpty else { return [:] }
        return try await get("friends/releases", query: [.init(name: "setIds", value: setIds.joined(separator: ","))])
    }

    func setFriends(_ setId: String) async throws -> SetFriends {
        try await get("friends/releases/\(setId)")
    }

    /// Un pseudo ne contient que des caractères sûrs, mais il voyage dans un chemin.
    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
