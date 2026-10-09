import Foundation

/// `Codable` et non `Decodable` : c'est l'encodage synthétisé qui fournit les `CodingKeys`
/// dont l'init manuel ci-dessous a besoin.
nonisolated struct PublicUser: Codable, Hashable, Sendable {
    nonisolated enum Role: String, Codable, Sendable { case user = "USER", admin = "ADMIN" }

    let id: String
    let email: String
    let username: String
    let role: Role
    let createdAt: String
    /// Chemin servi par l'API (`/uploads/…`), absent des versions antérieures du serveur.
    let avatarUrl: String?
    /**
     Langue dans laquelle l'utilisateur range sa collection, indépendante de celle de
     l'interface. `nil` tant qu'il n'a rien choisi — ou si le serveur est antérieur au
     réglage : la distinction compte, on ne propose pas de normaliser une collection vers
     une langue que personne n'a demandée.
     */
    let collectionLanguage: CardLanguage?

    var isAdmin: Bool { role == .admin }

    /// Une langue qu'on ne connaît pas encore vaut « pas de choix » : elle ne doit pas faire
    /// échouer le décodage de la session, c'est-à-dire empêcher de se connecter.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        username = try c.decode(String.self, forKey: .username)
        role = try c.decode(Role.self, forKey: .role)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        // Absente, nulle, ou d'une valeur qu'on ne connaît pas encore : dans les trois cas
        // « pas de choix », jamais une erreur de décodage.
        collectionLanguage = try? c.decode(CardLanguage.self, forKey: .collectionLanguage)
    }
}

/// Réponse de /auth/login, /auth/register et /auth/refresh avec `X-Auth-Mode: token`.
nonisolated struct TokenSession: Decodable, Sendable {
    let user: PublicUser
    let accessToken: String
    let refreshToken: String
    /// Secondes
    let accessExpiresIn: Int
    let refreshExpiresIn: Int
}

nonisolated struct LoginBody: Encodable, Sendable {
    let email: String
    let password: String
}

nonisolated struct RegisterBody: Encodable, Sendable {
    let email: String
    let username: String
    let password: String
}

nonisolated struct RefreshBody: Encodable, Sendable {
    let refreshToken: String
}

// MARK: - Statut serveur

nonisolated struct HealthStatus: Decodable, Sendable {
    let status: String
}

/// GET /meta-decks/status (peut être null tant que la meta n'a jamais été calculée).
nonisolated struct SyncStatus: Decodable, Sendable {
    let lastSyncAt: String?
    let lastStatus: String?
    let lastError: String?
    let cardCount: Int
}

nonisolated struct MetaSyncResult: Decodable, Sendable {
    let fetched: Int
    let lists: Int
    let archetypes: Int
    let staples: Int
}
