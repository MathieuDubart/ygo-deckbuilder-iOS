import Foundation

nonisolated struct DeckGuideRequest: Encodable, Sendable {
    let name: String?
    let cards: [DeckCardEntry]
    /// false = guide calculé uniquement
    let ai: Bool
}

nonisolated struct DeckGuide: Decodable, Sendable {
    nonisolated enum Source: String, Decodable, Sendable { case rules = "RULES", ai = "AI" }
    nonisolated enum AIStatus: String, Decodable, Sendable {
        case off = "OFF", pending = "PENDING", ready = "READY", error = "ERROR"
    }

    nonisolated struct Stat: Decodable, Hashable, Sendable {
        nonisolated enum Tone: String, Decodable, Sendable { case good, warn, bad, neutral }
        let label: String
        let value: String
        let hint: String
        let tone: Tone
    }

    nonisolated struct KeyCard: Decodable, Hashable, Sendable {
        let cardId: Int
        let roles: [GuideRole]
        let why: String
    }

    nonisolated struct Combo: Decodable, Hashable, Sendable {
        nonisolated struct Step: Decodable, Hashable, Sendable {
            let text: String
            let cardIds: [Int]
        }

        let title: String
        let handIds: [Int]
        let steps: [Step]
        let endBoardIds: [Int]
    }

    let source: Source
    let model: String?
    let aiAvailable: Bool
    let aiStatus: AIStatus
    let aiError: String?
    let readable: Bool
    let summary: String
    let styles: [String]
    let stats: [Stat]
    let gamePlan: [String]
    let keyCards: [KeyCard]
    let combos: [Combo]
    let goingFirst: [String]
    let goingSecond: [String]
    let mistakes: [String]
    let tips: [String]
    /// Cartes citées (id → résumé)
    let cards: [String: CardSummary]

    func card(_ id: Int) -> CardSummary? { cards[String(id)] }
}
