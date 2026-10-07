import Foundation
import Observation
import SwiftUI

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
    /// Étiquettes personnelles : création, renommage, pose ou retrait.
    private(set) var tagsVersion = 0
    /// Profil, amitiés, demandes : tout ce qui change ce que l'on voit des autres.
    private(set) var socialVersion = 0
    /// Demandes d'ami reçues : le seul chiffre de l'app qui appelle une action.
    private(set) var pendingRequests = 0
    /// Les étiquettes de l'utilisateur, chargées une fois pour toute l'app : c'est un petit
    /// référentiel que cinq écrans affichent, pas la peine que chacun le redemande.
    private(set) var tags: [Tag] = []
    /// Observé, pas ignoré : les vues qui n'affichent que des puces d'étiquette ne lisent
    /// que ce dictionnaire, et doivent se redessiner quand le référentiel arrive.
    private var tagsById: [String: Tag] = [:]

    /// Deck à ouvrir dans l'onglet Decks (après création depuis une suggestion ou un produit).
    var pendingDeckId: String?
    var selectedTab: AppTab = .collection
    /// Pile de navigation de l'onglet « Autre » (règles, wishlist, duel, catalogue).
    /// Hétérogène : la pile « Autre » empile des `MoreRoute`, mais aussi des `ProfileRoute`
    /// quand on ouvre le profil de quelqu'un depuis la liste d'amis. Un chemin typé ne peut
    /// porter qu'un seul type, et les liens des autres types y seraient inertes.
    var morePath = NavigationPath()
    /// Incrémenté quand on retape l'onglet où on est déjà : l'écran racine concerné revient
    /// en haut de sa pile (réflexe iOS). Chaque écran vérifie que c'est bien le sien.
    private(set) var rootTaps = 0
    /// Deck à tester dans l'onglet Duel (depuis le deck builder).
    var pendingDuelDeckId: String?

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
        morePath = NavigationPath()
        tags = []
        tagsById = [:]
        pendingRequests = 0
        show(.collection)
    }

    // MARK: - Invalidation

    func collectionChanged() {
        collectionVersion += 1
        decksVersion += 1
    }

    func decksChanged() { decksVersion += 1 }

    func wishlistChanged() { wishlistVersion += 1 }

    /// Profil modifié, amitié nouée ou rompue, demande envoyée ou traitée.
    func socialChanged() {
        socialVersion += 1
    }

    /// Recharge le compteur de demandes reçues (écran racine, sur `socialVersion`).
    func loadPendingRequests() async {
        guard case .signedIn = session else { return }
        guard let requests = try? await api.friendRequests() else { return }
        pendingRequests = requests.count { $0.direction == .incoming }
    }

    /// Une étiquette posée ou retirée change ce que les listes filtrées renvoient.
    func tagsChanged() {
        tagsVersion += 1
        collectionVersion += 1
    }

    /// Recharge le référentiel d'étiquettes (appelé par l'écran racine sur `tagsVersion`).
    func loadTags() async {
        guard case .signedIn = session else { return }
        guard let loaded = try? await api.tags() else { return }
        tags = loaded
        // Deux étiquettes de même identifiant ne devraient pas arriver, mais un doublon
        // ne doit pas faire tomber l'app au lancement.
        tagsById = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Les étiquettes posées sur une cible, dans l'ordre renvoyé par le serveur.
    func tags(for ids: [String]) -> [Tag] { ids.compactMap { tagsById[$0] } }

    /// Changement de langue ou de compte : tout recharger (noms de cartes, guides…).
    func refreshAll() {
        collectionVersion += 1
        decksVersion += 1
        wishlistVersion += 1
        tagsVersion += 1
    }

    func testInDuel(_ deckId: String) {
        pendingDuelDeckId = deckId
        openMore(.duel)
    }

    /// Dernier onglet choisi par le code, et quand. La barre d'onglets réécrit parfois la
    /// sélection derrière nous (elle resynchronise son contrôleur) : sans ce témoin on
    /// prendrait cet écho pour un tap sur l'onglet déjà actif, et la pile de l'onglet se
    /// viderait juste après qu'un écran y a poussé sa destination.
    @ObservationIgnored private var programmaticTab: (tab: AppTab, at: Date)?

    /// Un écho arrive dans la foulée du changement programmatique ; un vrai re-tap vient
    /// plus tard. Sans cette fenêtre, le témoin resterait armé et avalerait le prochain
    /// re-tap sur l'onglet où l'on vient justement d'envoyer l'utilisateur.
    private static let echoWindow: TimeInterval = 0.6

    /// Changement d'onglet venu du code, jamais de la barre d'onglets.
    func show(_ tab: AppTab) {
        programmaticTab = (tab, Date())
        selectedTab = tab
    }

    /// Sélection depuis la barre d'onglets : retaper l'onglet actif demande un retour en haut.
    func selectTab(_ tab: AppTab) {
        // Le témoin survit à l'écho (la barre peut réécrire deux fois) et meurt au vrai tap.
        let echo = programmaticTab.map {
            $0.tab == tab && Date().timeIntervalSince($0.at) < Self.echoWindow
        } ?? false
        if !echo {
            programmaticTab = nil
            if tab == selectedTab { rootTaps += 1 }
        }
        selectedTab = tab
    }

    /// Ouvre un écran de l'onglet « Autre » (remplace la pile en cours).
    func openMore(_ route: MoreRoute) {
        morePath = NavigationPath([route])
        show(.more)
    }

    func openDeck(_ id: String) {
        decksChanged()
        pendingDeckId = id
        show(.decks)
    }
}

enum AppTab: Hashable {
    case collection, decks, suggestions, more
}

/// Écrans regroupés sous l'onglet « Autre ».
enum MoreRoute: Hashable {
    case rules, wishlist, duel, catalog, friends, profile
}
