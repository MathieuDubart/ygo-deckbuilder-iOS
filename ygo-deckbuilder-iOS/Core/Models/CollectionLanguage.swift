import Foundation

/// Répartition d'une langue dans la collection : piles et exemplaires.
nonisolated struct LanguageCount: Codable, Hashable, Sendable, Identifiable {
    let language: CardLanguage
    let piles: Int
    let copies: Int

    var id: CardLanguage { language }
}

/// Ce que normaliser vers `target` coûterait, avant de l'avoir fait.
nonisolated struct CollectionLanguageReport: Codable, Hashable, Sendable {
    let target: CardLanguage
    /// Les langues les plus nombreuses d'abord.
    let byLanguage: [LanguageCount]
    /// Piles qui changeraient de langue.
    let affected: Int
    /// Piles qui disparaîtraient, absorbées par une pile devenue identique.
    let merged: Int

    var copies: Int { byLanguage.reduce(0) { $0 + $1.copies } }
}

nonisolated struct CollectionLanguageState: Codable, Hashable, Sendable {
    /// Choix explicite, ou nil tant que personne n'a tranché.
    let language: CardLanguage?
    /// Celle qui s'applique aujourd'hui : le choix, sinon la langue de la requête.
    let effective: CardLanguage
    let report: CollectionLanguageReport
}

nonisolated struct CollectionLanguageBody: Encodable, Sendable {
    let language: CardLanguage
    /// Appliquer aussi le choix aux cartes déjà en collection.
    let normalize: Bool
}

nonisolated struct CollectionLanguageResult: Decodable, Sendable {
    let target: CardLanguage
    let retagged: Int
    let merged: Int
}

/**
 Résolution d'un code imprimé lu par le scanner. Le statut dit où ça a coincé : la lecture,
 notre catalogue (extension inconnue), ou le numéro lui-même. Sans cette distinction, un
 catalogue en retard et un code mal lu donnent le même « introuvable ».
 */
nonisolated struct PrintLookup: Decodable, Sendable {
    nonisolated enum Status: String, Decodable, Sendable {
        case found = "FOUND"
        case invalidCode = "INVALID_CODE"
        case unknownSet = "UNKNOWN_SET"
        case unknownNumber = "UNKNOWN_NUMBER"
        /// Statut qu'on ne connaît pas encore : un serveur plus récent ne doit pas faire
        /// échouer le décodage, sinon le scan se réduirait à « introuvable » sans raison.
        case unrecognized

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unrecognized
        }
    }

    let status: Status
    let code: String
    let card: CardDetail?
    /// Nom de l'extension rattrapée à la volée, si le serveur a dû aller la chercher.
    let imported: String?
}
