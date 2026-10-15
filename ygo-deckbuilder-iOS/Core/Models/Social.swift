import Foundation

/// Profils et amitiés (cf. packages/shared/src/schemas/social.ts).
/// Deux personnes amies voient le profil de l'autre et son avancement par extension — rien
/// de plus : la collection complète d'un ami n'est pas consultable.

/// Un compte vu de l'extérieur. Jamais l'e-mail : ce n'est pas une donnée sociale.
nonisolated struct PublicProfile: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let username: String
    /// Chemins servis par l'API, à rendre absolus avec `APIClient.absoluteURL`.
    let avatarUrl: String?
    let bannerUrl: String?

    /// Première lettre du pseudo, pour l'avatar par défaut.
    var initial: String { username.prefix(1).uppercased() }
}

nonisolated enum FriendshipState: String, Decodable, Hashable, Sendable {
    case `self` = "SELF"
    case none = "NONE"
    case friends = "FRIENDS"
    case requestSent = "REQUEST_SENT"
    case requestReceived = "REQUEST_RECEIVED"

    /// Un état inconnu d'une version plus récente du serveur ne doit pas casser l'écran.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FriendshipState(rawValue: raw) ?? .none
    }
}

nonisolated struct UserSearchResult: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let username: String
    let avatarUrl: String?
    let bannerUrl: String?
    let state: FriendshipState
    /// Demande en cours, pour l'accepter ou l'annuler sans la rechercher.
    let requestId: String?

    var user: PublicProfile {
        PublicProfile(id: id, username: username, avatarUrl: avatarUrl, bannerUrl: bannerUrl)
    }
}

nonisolated struct FriendRequest: Decodable, Hashable, Sendable, Identifiable {
    nonisolated enum Direction: String, Decodable, Sendable { case incoming = "INCOMING", outgoing = "OUTGOING" }

    let id: String
    /// L'autre personne, jamais soi-même.
    let user: PublicProfile
    let direction: Direction
    let createdAt: String
}

/// Repères de collection partagés entre amis (pas la collection elle-même).
nonisolated struct SocialStats: Decodable, Hashable, Sendable {
    let distinctCards: Int
    let copies: Int
    let sets: Int
    let completedSets: Int
}

nonisolated struct Friend: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let username: String
    let avatarUrl: String?
    let bannerUrl: String?
    let friendsSince: String
    let stats: SocialStats

    var user: PublicProfile {
        PublicProfile(id: id, username: username, avatarUrl: avatarUrl, bannerUrl: bannerUrl)
    }
}

/// Une carte mise en avant : l'impression possédée, pas seulement la carte.
nonisolated struct ProfileCard: Decodable, Hashable, Sendable, Identifiable {
    let printId: String
    let printCode: String
    let rarity: String
    let setName: String
    let card: CardSummary

    var id: String { printId }
}

/**
 Profil, dans ses deux formes. Le serveur renvoie une union discriminée par `visible` : un
 profil qu'on n'a pas le droit de voir porte quand même pseudo et avatar, pour pouvoir
 demander la personne en ami. Le décodeur sépare les deux cas pour que l'interface ne puisse
 pas lire des compteurs à zéro en croyant que c'est la réalité.
 */
nonisolated enum ProfileView: Decodable, Sendable {
    case visible(Profile)
    case hidden(user: PublicProfile, state: FriendshipState, requestId: String?)

    private enum Keys: String, CodingKey { case visible, user, state, requestId }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        if try container.decode(Bool.self, forKey: .visible) {
            self = .visible(try Profile(from: decoder))
        } else {
            self = .hidden(
                user: try container.decode(PublicProfile.self, forKey: .user),
                state: try container.decode(FriendshipState.self, forKey: .state),
                requestId: try container.decodeIfPresent(String.self, forKey: .requestId))
        }
    }

    var user: PublicProfile {
        switch self {
        case .visible(let profile): profile.user
        case .hidden(let user, _, _): user
        }
    }
}

nonisolated struct Profile: Decodable, Sendable {
    let user: PublicProfile
    let state: FriendshipState
    /// Date depuis laquelle on est amis, nil sinon (profil propre inclus).
    let friendsSince: String?
    let friendCount: Int
    let stats: SocialStats
    let cards: [ProfileCard]
    let memberSince: String

    var isSelf: Bool { state == .`self` }
}

/// Avancement d'un ami sur une extension, dans les deux lectures habituelles.
nonisolated struct FriendSetProgress: Decodable, Hashable, Sendable, Identifiable {
    let user: PublicProfile
    let prints: Int
    let cards: Int
    let ownedPrints: Int
    let ownedCards: Int

    var id: String { user.id }

    func owned(anyEdition: Bool) -> Int { anyEdition ? ownedCards : ownedPrints }
    func total(anyEdition: Bool) -> Int { anyEdition ? cards : prints }

    func ratio(anyEdition: Bool) -> Double {
        let total = total(anyEdition: anyEdition)
        guard total > 0 else { return 0 }
        return min(1, Double(owned(anyEdition: anyEdition)) / Double(total))
    }
}

/**
 Qui possède quoi dans une extension. `owners` est indexé par impression : la grille se lit
 carte par carte, et une impression n'a qu'une poignée de propriétaires alors qu'un ami peut
 en posséder des centaines.
 */
nonisolated struct SetFriends: Decodable, Sendable {
    let friends: [FriendSetProgress]
    /// printId → amis qui possèdent cette impression exacte.
    let owners: [String: [String]]
    /// printId → amis qui possèdent la carte dans une autre édition.
    let ownersAnyEdition: [String: [String]]

    static let empty = SetFriends(friends: [], owners: [:], ownersAnyEdition: [:])

    /// Index des amis par identifiant : les grilles ne portent que des identifiants.
    var byId: [String: PublicProfile] {
        Dictionary(friends.map { ($0.user.id, $0.user) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Avancement des amis sur plusieurs extensions (liste des extensions).
typealias FriendsProgress = [String: [FriendSetProgress]]

// MARK: - Corps de requête

nonisolated struct FriendRequestBody: Encodable, Sendable {
    let username: String
}

/**
 Réglages du compte. Le serveur laisse tel quel tout champ absent du corps, et seul un `null`
 explicite efface une préférence — d'où les doubles optionnels : `nil` veut dire « ne touche
 pas », `.some(nil)` veut dire « efface ».
 */
nonisolated struct UpdateProfileBody: Encodable, Sendable {
    // Défauts explicites : l'init mémberwise doit permettre de ne fournir qu'un seul champ.
    var username: String? = nil
    var marketLanguage: CardLanguage?? = nil
    var marketMinCondition: CardCondition?? = nil

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(username, forKey: .username)
        // `encodeIfPresent` traiterait un double optionnel comme une simple absence : on
        // distingue donc à la main « ne touche pas » de « écris null ».
        if let language = marketLanguage { try c.encode(language, forKey: .marketLanguage) }
        if let condition = marketMinCondition {
            try c.encode(condition, forKey: .marketMinCondition)
        }
    }

    enum CodingKeys: String, CodingKey {
        case username, marketLanguage, marketMinCondition
    }
}

nonisolated struct ProfileCardsBody: Encodable, Sendable {
    let printIds: [String]
}

nonisolated struct UploadedImage: Decodable, Sendable {
    let url: String
}

/// Limite côté serveur, répétée ici pour que l'interface arrête la sélection au bon endroit.
nonisolated let maxProfileCards = 12
