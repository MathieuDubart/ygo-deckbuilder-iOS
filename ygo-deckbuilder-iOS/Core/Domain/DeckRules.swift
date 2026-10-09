import Foundation

/**
 Statut banlist, normalisé. Les sources ne s'accordent pas sur les libellés — YGOPRODeck écrit
 « Banned », Konami « Forbidden » — alors qu'il n'existe que trois statuts. On normalise à
 l'entrée, une fois.
 */
nonisolated enum BanStatus: String, Sendable {
    case forbidden
    case limited
    case semiLimited

    init?(label: String?) {
        guard let label else { return nil }
        // Les suites de blancs se replient en UN séparateur, comme le /[\s_]+/ du web :
        // « Semi  Limited » et « Semi\tLimited » circulent, et les manquer rendrait la carte
        // jouable en trois exemplaires au lieu de deux.
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "_"))
        let parts = label.lowercased().components(separatedBy: separators).filter { !$0.isEmpty }
        switch parts.joined(separator: "-") {
        case "banned", "forbidden": self = .forbidden
        case "limited": self = .limited
        case "semi-limited": self = .semiLimited
        default: return nil
        }
    }

    /**
     Exemplaires autorisés. La limite porte sur le deck ENTIER : Main + Extra + Side confondus.
     C'est ce qui fait qu'envoyer une carte au Side ne répare jamais un dépassement.
     */
    var maxCopies: Int {
        switch self {
        case .forbidden: 0
        case .limited: 1
        case .semiLimited: 2
        }
    }

    /// Clé de traduction du statut (`cards.ban.*`), partagée avec le web.
    var messageKey: String {
        switch self {
        case .forbidden: "FORBIDDEN"
        case .limited: "LIMITED"
        case .semiLimited: "SEMI_LIMITED"
        }
    }
}

/// Règles officielles de construction : portage de packages/shared/src/domain/deck-rules.ts.
nonisolated enum DeckRules {
    static let maxCopies = 3

    static func range(_ zone: DeckZone) -> ClosedRange<Int> {
        switch zone {
        case .main: 40...60
        case .extra: 0...15
        case .side: 0...15
        }
    }

    /// Exemplaires autorisés selon le statut banlist.
    static func maxCopies(for banStatus: String?) -> Int {
        BanStatus(label: banStatus)?.maxCopies ?? maxCopies
    }

    /**
     La banlist qui s'applique à une carte dans un deck donné : celle de son format. Les deux
     listes divergent — une carte limitée en TCG peut être libre en OCG — donc se tromper de
     colonne interdit des cartes légales, ou laisse passer des cartes interdites.
     */
    static func banStatus(of card: CardSummary, format: DeckFormat) -> String? {
        format == .ocg ? card.banOcg : card.banTcg
    }

    nonisolated struct Entry: Sendable {
        let cardId: Int
        let zone: DeckZone
        let quantity: Int
        let isExtraDeckMonster: Bool
        let banStatus: String?
    }

    /// Validation pure d'une decklist (feedback instantané dans le builder).
    static func validate(_ entries: [Entry]) -> [DeckIssue] {
        var issues: [DeckIssue] = []
        var zoneCounts: [DeckZone: Int] = [:]
        var copies: [Int: (count: Int, limit: Int)] = [:]
        var order: [Int] = []

        for e in entries {
            zoneCounts[e.zone, default: 0] += e.quantity
            if e.zone == .main && e.isExtraDeckMonster || e.zone == .extra && !e.isExtraDeckMonster {
                issues.append(DeckIssue(code: .wrongZone, zone: e.zone, cardId: e.cardId))
            }
            if copies[e.cardId] == nil { order.append(e.cardId) }
            copies[e.cardId] = (
                (copies[e.cardId]?.count ?? 0) + e.quantity,
                copies[e.cardId]?.limit ?? maxCopies(for: e.banStatus)
            )
        }

        for zone in DeckZone.allCases {
            let count = zoneCounts[zone] ?? 0
            let r = range(zone)
            if count < r.lowerBound {
                issues.append(DeckIssue(code: .zoneTooSmall, zone: zone, count: count, limit: r.lowerBound))
            }
            if count > r.upperBound {
                issues.append(DeckIssue(code: .zoneTooLarge, zone: zone, count: count, limit: r.upperBound))
            }
        }

        for id in order {
            guard let c = copies[id], c.count > c.limit else { continue }
            // Une interdiction n'est pas un quota : « 2 exemplaires sur 0 » ne veut rien dire
            if c.limit == 0 {
                issues.append(DeckIssue(code: .forbidden, cardId: id, count: c.count))
            } else {
                issues.append(
                    DeckIssue(code: .tooManyCopies, cardId: id, count: c.count, limit: c.limit))
            }
        }
        return issues
    }

    /// Un exemplaire à retirer d'une zone précise.
    nonisolated struct Fix: Sendable, Hashable {
        let cardId: Int
        let zone: DeckZone
        let remove: Int
    }

    /**
     Ce qu'il faut retirer pour qu'une decklist repasse la banlist, et rien d'autre : une carte
     trop jouée perd ses exemplaires au-delà de la limite, une carte interdite part en entier.
     On ne déplace rien vers le Side — la limite compte le deck entier, donc déplacer un
     exemplaire ne le fait pas disparaître du total.

     Le Side est sacrifié en premier : c'est la réserve, la retoucher ne défait pas le deck
     qu'on joue. Le résultat doit être identique à `banlistFixes()` côté web, au même ordre
     près : c'est le même bouton, il doit faire la même chose.
     */
    static func fixes(_ entries: [Entry]) -> [Fix] {
        var copies: [Int: (count: Int, limit: Int)] = [:]
        var order: [Int] = []
        for e in entries {
            if copies[e.cardId] == nil { order.append(e.cardId) }
            copies[e.cardId] = (
                (copies[e.cardId]?.count ?? 0) + e.quantity,
                copies[e.cardId]?.limit ?? maxCopies(for: e.banStatus)
            )
        }

        var result: [Fix] = []
        for id in order {
            guard let c = copies[id] else { continue }
            var excess = c.count - c.limit
            guard excess > 0 else { continue }
            for zone in [DeckZone.side, .extra, .main] where excess > 0 {
                let inZone = entries
                    .filter { $0.cardId == id && $0.zone == zone }
                    .reduce(0) { $0 + $1.quantity }
                guard inZone > 0 else { continue }
                let remove = min(inZone, excess)
                result.append(Fix(cardId: id, zone: zone, remove: remove))
                excess -= remove
            }
        }
        return result
    }
}

/// Code d'impression écrit sur la carte : "SDBE-FR001", "LOB-EN001", "MP22-FR266"…
nonisolated struct PrintCode: Hashable, Sendable {
    let set: String
    let number: String
    /// Région lue dans le code (FR, EN…), si présente.
    let region: String?

    init?(_ text: String) {
        let pattern = #/\s*([A-Za-z0-9]{2,5})-([A-Za-z]{0,2})(\d{2,4})\s*/#
        guard let m = text.wholeMatch(of: pattern) else { return nil }
        set = String(m.1).uppercased()
        number = String(m.3)
        region = m.2.isEmpty ? nil : String(m.2).uppercased()
    }

    /// "SDBE-EN001" correspond-il au code scanné "SDBE-FR001" ? (la langue est ignorée)
    func matches(_ printCode: String) -> Bool {
        guard let other = PrintCode(printCode) else { return false }
        return other.set == set && other.number == number
    }

    var text: String { "\(set)-\(region ?? "")\(number)" }
}
