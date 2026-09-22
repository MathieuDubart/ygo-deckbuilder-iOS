import Foundation
import Observation

/// État global : serveur, session, et « versions » des données partagées entre écrans.
/// Un écran qui dépend de la collection se recharge avec `.task(id: app.collectionVersion)` ;
/// une action qui modifie la collection appelle `app.collectionChanged()`.
@Observable
final class AppState {
    enum Session: Equatable {
        case checking
        case signedOut
        case signedIn(PublicUser)
    }

    let server = ServerConfig()
    let api: APIClient
    private(set) var session: Session = .checking

    /// Données touchées par une modif de la collection (quantités, suggestions, decks…).
    private(set) var collectionVersion = 0
    private(set) var decksVersion = 0
    private(set) var wishlistVersion = 0

    /// Deck à ouvrir dans l'onglet Decks (après création depuis une suggestion ou un produit).
    var pendingDeckId: String?
    var selectedTab: AppTab = .collection

    init() {
        api = APIClient(server: server, tokens: TokenStore())
        ImagePipeline.shared.server = server.url
        api.onSessionExpired = { [weak self] in self?.session = .signedOut }
    }

    var user: PublicUser? {
        if case .signedIn(let user) = session { return user }
        return nil
    }

    // MARK: - Session

    /// Au lancement : reprend la session du Keychain si elle est encore valide.
    func restore() async {
        guard server.url != nil else {
            session = .signedOut
            return
        }
        if await api.refreshSession(), let user = api.lastUser {
            session = .signedIn(user)
        } else {
            session = .signedOut
        }
    }

    func useServer(_ url: URL) {
        server.url = url
        ImagePipeline.shared.server = url
        session = .signedOut
    }

    func forgetServer() async {
        await signOut()
        server.url = nil
        ImagePipeline.shared.server = nil
    }

    func login(email: String, password: String) async throws {
        session = .signedIn(try await api.login(email: email, password: password))
        refreshAll()
    }

    func register(email: String, username: String, password: String) async throws {
        session = .signedIn(try await api.register(email: email, username: username, password: password))
        refreshAll()
    }

    func signOut() async {
        await api.signOut()
        session = .signedOut
        selectedTab = .collection
    }

    // MARK: - Invalidation

    func collectionChanged() {
        collectionVersion += 1
        decksVersion += 1
    }

    func decksChanged() { decksVersion += 1 }

    func wishlistChanged() { wishlistVersion += 1 }

    /// Changement de langue ou de compte : tout recharger (noms de cartes, guides…).
    func refreshAll() {
        collectionVersion += 1
        decksVersion += 1
        wishlistVersion += 1
    }

    func openDeck(_ id: String) {
        decksChanged()
        pendingDeckId = id
        selectedTab = .decks
    }
}

enum AppTab: Hashable {
    case collection, decks, suggestions, wishlist, search
}
