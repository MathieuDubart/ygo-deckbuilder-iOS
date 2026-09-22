import Foundation
import Security

/// Tokens de session. Le refresh token (longue durée) est rangé dans le Keychain, par serveur ;
/// l'access token (15 min) reste en mémoire.
final class TokenStore {
    private(set) var accessToken: String?
    private let service = "ygo-deckbuilder.session"

    func refreshToken(for server: URL) -> String? {
        var query = baseQuery(server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ session: TokenSession, for server: URL) {
        accessToken = session.accessToken
        let data = Data(session.refreshToken.utf8)
        let query = baseQuery(server)
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func clear(for server: URL) {
        accessToken = nil
        SecItemDelete(baseQuery(server) as CFDictionary)
    }

    private func baseQuery(_ server: URL) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: server.absoluteString,
        ]
    }
}
