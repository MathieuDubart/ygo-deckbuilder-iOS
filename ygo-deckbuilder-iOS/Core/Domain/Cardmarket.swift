import Foundation

/**
 Liens vers Cardmarket, la place de marché européenne où l'on achète les cartes à l'unité.

 Portage de `packages/shared/src/domain/cardmarket.ts` : les deux doivent rester d'accord,
 un lien qui diffère entre le web et l'app étant un lien faux d'un côté. Tout est construit
 ici, sans réseau : Cardmarket n'a pas d'API publique utilisable sans compte vendeur, et
 leur site est derrière une protection anti-robot. On ne lit donc jamais leurs pages — on
 fabrique une URL que l'utilisateur ouvre lui-même, où il est déjà connecté.

 Deux limites assumées, qui expliquent la forme de ce module :

 1. **On passe par la recherche, pas par la fiche produit.** Une fiche a l'adresse
    `/Products/Singles/<Extension>/<Carte>`, mais ces deux morceaux sont les noms de
    Cardmarket, qui ne sont pas ceux de notre catalogue (YGOPRODeck). Deviner le libellé
    d'une extension donnerait un 404 ; une recherche sur le nom anglais tombe toujours juste.
 2. **Il n'existe pas de panier pré-rempli par URL.** L'ajout passe par une session
    connectée, carte par carte. Pour un deck entier on produit donc un texte à coller
    (`wantsListText`), que l'assistant d'achat de Cardmarket sait ensuite exploiter.
 */
nonisolated enum Cardmarket {
    private static let host = "www.cardmarket.com"

    /// Les cinq langues d'interface de Cardmarket. Les autres retombent sur l'anglais.
    private static let siteLocales: Set<String> = ["en", "fr", "de", "it", "es"]

    /**
     Identifiants de langue de Cardmarket, tels que leur API les documente. Les langues
     qu'ils ne numérotent pas publiquement (japonais, coréen, portugais) sont absentes
     exprès : sans identifiant sûr, mieux vaut une fiche non filtrée qu'un filtre au hasard.
     */
    private static let languageIds: [CardLanguage: Int] = [
        .en: 1, .fr: 2, .de: 3, .es: 4, .it: 5,
    ]

    /**
     Les langues sur lesquelles on sait filtrer, dans l'ordre d'affichage. C'est la liste à
     proposer dans un réglage : offrir le japonais donnerait un choix sans effet, ce qui est
     pire que ne pas l'offrir.
     */
    static let languages: [CardLanguage] = [.en, .fr, .de, .es, .it]

    /**
     État minimum accepté. Cardmarket ordonne les états exactement comme nous
     (`CardCondition.allCases`), du meilleur au pire, et les numérote à partir de 1 — d'où la
     position dans la liste.
     */
    private static func conditionId(_ condition: CardCondition) -> Int {
        (CardCondition.allCases.firstIndex(of: condition) ?? 0) + 1
    }

    /// Ce que l'utilisateur veut voir en arrivant sur une fiche. Tout est facultatif.
    nonisolated struct Preferences: Hashable, Sendable {
        /// Langue des exemplaires cherchés. Par défaut, celle de rangement de la collection.
        var language: CardLanguage?
        /// État minimum accepté.
        var minCondition: CardCondition?

        init(language: CardLanguage? = nil, minCondition: CardCondition? = nil) {
            self.language = language
            self.minCondition = minCondition
        }
    }

    /**
     Lien vers une carte, filtré selon les préférences.

     `nameEn` est le nom ANGLAIS : c'est celui que Cardmarket indexe, et un nom français n'y
     renvoie rien. Les filtres s'appliquent au tableau des offres une fois sur la fiche ; sur
     la page de résultats ils sont simplement ignorés, ce qui ne coûte rien.
     */
    static func searchURL(
        _ nameEn: String, preferences: Preferences = .init(), locale: String = "en"
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/\(siteLocales.contains(locale) ? locale : "en")/YuGiOh/Products/Search"
        var items = [URLQueryItem(name: "searchString", value: nameEn)]
        if let language = preferences.language, let id = languageIds[language] {
            items.append(URLQueryItem(name: "language", value: String(id)))
        }
        if let condition = preferences.minCondition {
            items.append(URLQueryItem(name: "minCondition", value: String(conditionId(condition))))
        }
        components.queryItems = items
        // `URLComponents` laisse passer un « + » tel quel, et un serveur le relit comme une
        // espace. Le web encode avec `encodeURIComponent`, qui l'échappe : on fait pareil.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Les listes de souhaits de l'utilisateur, où se colle le texte produit ci-dessous.
    static func wantsURL(locale: String = "en") -> URL? {
        URL(string: "https://\(host)/\(siteLocales.contains(locale) ? locale : "en")/YuGiOh/Wants")
    }

    /// Une ligne de la liste à coller : une carte, et combien il en manque.
    nonisolated struct Wanted: Hashable, Sendable {
        let nameEn: String
        let quantity: Int
    }

    /**
     Le texte à coller dans une liste de souhaits : une ligne par carte, `quantité nom`.

     Volontairement sans extension ni rareté. Cardmarket nomme ses extensions autrement que
     notre catalogue, et une ligne dont l'extension n'est pas reconnue est rejetée entière —
     on perdrait la carte pour gagner une précision que l'acheteur ajuste de toute façon sur
     place. Les cartes sont rangées par nom pour que deux exports du même deck donnent le
     même texte, et les doublons sont cumulés : une carte demandée en main et en extra n'y
     figure qu'une fois. L'ordre exact peut différer de celui du web sur les noms à
     ponctuation, chacun triant selon sa propre collation — le contenu, lui, est le même.
     */
    static func wantsListText(_ cards: [Wanted]) -> String {
        var total: [String: Int] = [:]
        for card in cards where card.quantity > 0 {
            total[card.nameEn, default: 0] += card.quantity
        }
        return total.keys.sorted()
            .map { "\(total[$0] ?? 0) \($0)" }
            .joined(separator: "\n")
    }
}

nonisolated extension CardSummary {
    /**
     Le nom sous lequel cette carte se cherche sur une place de marché : l'anglais quand on
     l'a, sinon celui qu'on a. L'API ne renvoie `nameEn` que lorsqu'il diffère du nom
     affiché, donc son absence veut dire « le nom affiché EST l'anglais », pas « on ne sait
     pas ».
     */
    var marketName: String { nameEn ?? name }
}
