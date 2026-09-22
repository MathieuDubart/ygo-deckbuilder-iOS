import Foundation

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
        switch banStatus {
        case "Banned", "Forbidden": 0
        case "Limited": 1
        case "Semi-Limited": 2
        default: maxCopies
        }
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
                maxCopies(for: e.banStatus)
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
            issues.append(DeckIssue(code: .tooManyCopies, cardId: id, count: c.count, limit: c.limit))
        }
        return issues
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

    /// Langue de la carte déduite du code ("SDBE-FR001" → FR).
    var language: CardLanguage? { region.flatMap(CardLanguage.init(rawValue:)) }

    var text: String { "\(set)-\(region ?? "")\(number)" }
}
