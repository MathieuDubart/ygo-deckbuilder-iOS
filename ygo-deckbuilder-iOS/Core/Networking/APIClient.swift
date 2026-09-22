import Foundation
import Observation

/// Adresse du serveur (instance auto-hébergée), choisie au premier lancement.
@Observable
final class ServerConfig {
    private static let key = "server.url"

    var url: URL? {
        didSet { UserDefaults.standard.set(url?.absoluteString, forKey: Self.key) }
    }

    init() {
        url = UserDefaults.standard.string(forKey: Self.key).flatMap(URL.init(string:))
    }

    /// "ygo.example.com" → https://ygo.example.com ; garde http:// si précisé (réseau local).
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if text.hasSuffix("/api") { text.removeLast(4) }
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host() != nil
        else { return nil }
        return url
    }
}

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE"
}

/// Client HTTP unique. Tout passe par `<serveur>/api/…` (le proxy du front web relaie vers
/// l'API) : un seul port exposé, comme pour le navigateur. Sur un 401, UN refresh (mutualisé
/// entre requêtes concurrentes) puis on rejoue la requête.
final class APIClient {
    let server: ServerConfig
    let tokens: TokenStore
    /// Appelé quand la session est morte (refresh refusé) : retour à l'écran de connexion.
    var onSessionExpired: (() -> Void)?

    private let session: URLSession
    private var refreshing: Task<Bool, Never>?

    init(server: ServerConfig, tokens: TokenStore) {
        self.server = server
        self.tokens = tokens
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    // MARK: - Requêtes

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        try decode(try await data(.get, path, query: query))
    }

    func send<T: Decodable>(
        _ method: HTTPMethod, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil,
        as type: T.Type = T.self
    ) async throws -> T {
        try decode(try await data(method, path, query: query, body: body))
    }

    /// Requête sans corps de réponse utile (204, ou réponse ignorée).
    func perform(_ method: HTTPMethod, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil) async throws {
        _ = try await data(method, path, query: query, body: body)
    }

    func text(_ path: String) async throws -> String {
        String(decoding: try await data(.get, path), as: UTF8.self)
    }

    /// Requête brute : authentification, langue, refresh automatique.
    func data(
        _ method: HTTPMethod, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) async throws -> Data {
        let payload = try body.map { try JSONEncoder().encode($0) }
        var (data, status) = try await raw(method, path, query: query, payload: payload, authenticated: authenticated)
        if status == 401, authenticated {
            if await refreshSession() {
                (data, status) = try await raw(method, path, query: query, payload: payload, authenticated: true)
            } else {
                onSessionExpired?()
            }
        }
        guard (200..<300).contains(status) else { throw APIError.from(status: status, data: data) }
        return data
    }

    private func raw(
        _ method: HTTPMethod, _ path: String, query: [URLQueryItem], payload: Data?, authenticated: Bool
    ) async throws -> (Data, Int) {
        guard let base = server.url else { throw APIError(status: 0, message: t("ios.errors.noServer")) }
        var components = URLComponents(url: base.appending(path: "api").appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(L10n.shared.current.rawValue, forHTTPHeaderField: "Accept-Language")
        request.setValue("token", forHTTPHeaderField: "X-Auth-Mode")
        if let payload {
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated, let token = tokens.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(status: 0, message: t("ios.errors.decoding", ["detail": String(describing: error)]))
        }
    }

    // MARK: - Session

    /// Échange le refresh token du Keychain contre une nouvelle paire (un seul refresh à la fois :
    /// l'API révoque toute la session si un refresh token est réutilisé).
    func refreshSession() async -> Bool {
        if let refreshing { return await refreshing.value }
        let task = Task { [weak self] () -> Bool in
            guard let self, let server = self.server.url, let token = self.tokens.refreshToken(for: server) else {
                return false
            }
            do {
                let payload = try JSONEncoder().encode(RefreshBody(refreshToken: token))
                let (data, status) = try await self.raw(.post, "auth/refresh", query: [], payload: payload, authenticated: false)
                if status == 401 || status == 403 {
                    self.tokens.clear(for: server)
                    return false
                }
                guard (200..<300).contains(status) else { return false }
                let session = try JSONDecoder().decode(TokenSession.self, from: data)
                self.tokens.save(session, for: server)
                self.lastUser = session.user
                return true
            } catch {
                return false
            }
        }
        refreshing = task
        let ok = await task.value
        refreshing = nil
        return ok
    }

    /// Utilisateur renvoyé par le dernier refresh (évite un /auth/me au démarrage).
    private(set) var lastUser: PublicUser?

    func signIn(_ path: String, body: any Encodable) async throws -> PublicUser {
        guard let server = server.url else { throw APIError(status: 0, message: t("ios.errors.noServer")) }
        let response = try await self.data(.post, path, body: body, authenticated: false)
        let session: TokenSession = try decode(response)
        tokens.save(session, for: server)
        return session.user
    }

    func signOut() async {
        guard let server = server.url else { return }
        if let token = tokens.refreshToken(for: server) {
            try? await perform(.post, "auth/logout", body: RefreshBody(refreshToken: token))
        }
        tokens.clear(for: server)
    }
}
