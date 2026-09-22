import Foundation

nonisolated struct PublicUser: Codable, Hashable, Sendable {
    nonisolated enum Role: String, Codable, Sendable { case user = "USER", admin = "ADMIN" }

    let id: String
    let email: String
    let username: String
    let role: Role
    let createdAt: String

    var isAdmin: Bool { role == .admin }
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
