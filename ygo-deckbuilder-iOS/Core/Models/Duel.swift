import Foundation

// Simulateur de duel : miroir de packages/shared/src/schemas/duel.ts.
// Vue toujours du point de vue de l'utilisateur : joueur 0 = toi, joueur 1 = l'adversaire.

nonisolated enum DuelOpponentControl: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case passive = "PASSIVE", me = "ME", bot = "BOT"
    var id: String { rawValue }
}

nonisolated enum DuelChainPrompts: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case smart = "SMART", always = "ALWAYS"
    var id: String { rawValue }
}

nonisolated enum DuelSetupLocation: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case mzone = "MZONE", szone = "SZONE", fzone = "FZONE", hand = "HAND", grave = "GRAVE", banished = "BANISHED"
    var id: String { rawValue }
    var onField: Bool { self == .mzone || self == .szone }
}

nonisolated enum DuelSetupPosition: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case attack = "ATTACK", defense = "DEFENSE", set = "SET"
    var id: String { rawValue }
}

nonisolated enum DuelLocation: String, Codable, Hashable, Sendable {
    case deck = "DECK", hand = "HAND", mzone = "MZONE", szone = "SZONE", grave = "GRAVE"
    case banished = "BANISHED", extra = "EXTRA", overlay = "OVERLAY"
}

nonisolated enum DuelPosition: String, Codable, Hashable, Sendable {
    case atk = "ATK", def = "DEF", fdAtk = "FD_ATK", fdDef = "FD_DEF"
    var isDefense: Bool { self == .def || self == .fdDef }
    var isFaceDown: Bool { self == .fdAtk || self == .fdDef }
}

nonisolated enum DuelPhase: String, Codable, Hashable, Sendable, CaseIterable {
    case draw = "DRAW", standby = "STANDBY", main1 = "MAIN1", battle = "BATTLE", main2 = "MAIN2", end = "END"
}

// MARK: - Préparation

nonisolated struct DuelBoardCard: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var cardId: Int
    var location: DuelSetupLocation
    var position: DuelSetupPosition = .attack
    /// Zone 0–4 ; nil = première libre
    var zone: Int?

    private enum CodingKeys: String, CodingKey { case cardId, location, position, zone }
}

nonisolated struct DuelOpponentSetup: Codable, Hashable, Sendable {
    var control: DuelOpponentControl = .passive
    var deckId: String?
    var board: [DuelBoardCard] = []
}

nonisolated struct CreateDuelBody: Codable, Hashable, Sendable {
    var deckId: String = ""
    var goingFirst = true
    var openingHand: [Int] = []
    var startingLP = 8000
    var chainPrompts: DuelChainPrompts = .smart
    var opponent = DuelOpponentSetup()
}

// MARK: - État

nonisolated struct DuelCardRef: Codable, Hashable, Sendable {
    let controller: Int
    let location: DuelLocation
    let sequence: Int
    /// 0 = carte cachée
    let code: Int

    var key: String { "\(controller):\(location.rawValue):\(sequence)" }
}

nonisolated struct DuelCard: Decodable, Hashable, Sendable, Identifiable {
    let controller: Int
    let location: DuelLocation
    let sequence: Int
    let code: Int
    let position: DuelPosition?
    let attack: Int?
    let defense: Int?
    let level: Int?
    let rank: Int?
    let link: Int?
    let overlays: [Int]
    let counters: Int

    var ref: DuelCardRef { DuelCardRef(controller: controller, location: location, sequence: sequence, code: code) }
    var id: String { ref.key }
}

nonisolated struct DuelPlayer: Decodable, Hashable, Sendable {
    let lp: Int
    let deckCount: Int
    let extraCount: Int
    let hand: [DuelCard]
    /// 7 cases : 0–4 Zones Monstre Principales, 5–6 Zones Monstre Extra
    let monsters: [DuelCard?]
    /// 6 cases : 0–4 Zones Magie & Piège, 5 = Zone Terrain
    let spells: [DuelCard?]
    let grave: [DuelCard]
    let banished: [DuelCard]
    let extra: [DuelCard]
}

nonisolated struct DuelAction: Decodable, Hashable, Sendable {
    let kind: String
    let index: Int
    let card: DuelCardRef
    let description: String?
    let direct: Bool?
}

nonisolated struct DuelChoiceCard: Decodable, Hashable, Sendable, Identifiable {
    let index: Int
    let card: DuelCardRef
    let description: String?
    let value: Int?
    var id: Int { index }
    /// Niveau « bas » (une carte peut compter pour deux Niveaux)
    var level: Int { (value ?? 0) & 0xffff }
}

nonisolated struct DuelZone: Codable, Hashable, Sendable {
    let controller: Int
    let location: String
    let sequence: Int
    var key: String { "\(controller):\(location):\(sequence)" }
}

nonisolated struct DuelOption: Decodable, Hashable, Sendable, Identifiable {
    let index: Int
    let text: String
    var id: Int { index }
}

/// Ce que le moteur attend.
nonisolated struct DuelPrompt: Decodable, Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        case idle(actions: [DuelAction], canBattle: Bool, canEnd: Bool)
        case battle(actions: [DuelAction], canMain2: Bool, canEnd: Bool)
        case chain(options: [DuelChoiceCard], forced: Bool)
        case yesNo(text: String, card: DuelCardRef?)
        case option([DuelOption])
        case selectCards(mode: String, cards: [DuelChoiceCard], mustCards: [DuelChoiceCard], min: Int, max: Int, sum: Int?, cancelable: Bool)
        case selectUnselect(selectable: [DuelChoiceCard], unselectable: [DuelChoiceCard], canFinish: Bool, cancelable: Bool)
        case place(zones: [DuelZone], count: Int, disable: Bool)
        case position(code: Int, positions: [DuelPosition])
        case announceNumber([Int])
        case announce(race: Bool, choices: [String], count: Int)
        case announceCard
        case sort([DuelChoiceCard])
        case unknown
    }

    let id: Int
    let player: Int
    let hint: String?
    let kind: Kind

    private enum Keys: String, CodingKey {
        case id, player, hint, kind, actions, canBattle, canEnd, canMain2, options, forced, text, card, mode
        case cards, mustCards, min, max, sum, cancelable, selectable, unselectable, canFinish, zones, count
        case disable, code, positions, values, choices
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(Int.self, forKey: .id)
        player = try c.decode(Int.self, forKey: .player)
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
        func cards(_ key: Keys) throws -> [DuelChoiceCard] { try c.decodeIfPresent([DuelChoiceCard].self, forKey: key) ?? [] }
        func flag(_ key: Keys) throws -> Bool { try c.decodeIfPresent(Bool.self, forKey: key) ?? false }
        func int(_ key: Keys) throws -> Int { try c.decodeIfPresent(Int.self, forKey: key) ?? 0 }
        switch try c.decode(String.self, forKey: .kind) {
        case "IDLE":
            kind = .idle(actions: try c.decode([DuelAction].self, forKey: .actions), canBattle: try flag(.canBattle), canEnd: try flag(.canEnd))
        case "BATTLE":
            kind = .battle(actions: try c.decode([DuelAction].self, forKey: .actions), canMain2: try flag(.canMain2), canEnd: try flag(.canEnd))
        case "CHAIN":
            kind = .chain(options: try cards(.options), forced: try flag(.forced))
        case "YESNO":
            kind = .yesNo(text: try c.decodeIfPresent(String.self, forKey: .text) ?? "", card: try c.decodeIfPresent(DuelCardRef.self, forKey: .card))
        case "OPTION":
            kind = .option(try c.decode([DuelOption].self, forKey: .options))
        case "SELECT_CARDS":
            kind = .selectCards(
                mode: try c.decode(String.self, forKey: .mode), cards: try cards(.cards), mustCards: try cards(.mustCards),
                min: try int(.min), max: try int(.max), sum: try c.decodeIfPresent(Int.self, forKey: .sum),
                cancelable: try flag(.cancelable))
        case "SELECT_UNSELECT":
            kind = .selectUnselect(
                selectable: try cards(.selectable), unselectable: try cards(.unselectable),
                canFinish: try flag(.canFinish), cancelable: try flag(.cancelable))
        case "PLACE":
            kind = .place(zones: try c.decode([DuelZone].self, forKey: .zones), count: try int(.count), disable: try flag(.disable))
        case "POSITION":
            kind = .position(code: try int(.code), positions: try c.decode([DuelPosition].self, forKey: .positions))
        case "ANNOUNCE_NUMBER":
            kind = .announceNumber(try c.decode([Int].self, forKey: .values))
        case "ANNOUNCE_RACE":
            kind = .announce(race: true, choices: try c.decode([String].self, forKey: .choices), count: try int(.count))
        case "ANNOUNCE_ATTRIBUTE":
            kind = .announce(race: false, choices: try c.decode([String].self, forKey: .choices), count: try int(.count))
        case "ANNOUNCE_CARD":
            kind = .announceCard
        case "SORT":
            kind = .sort(try cards(.cards))
        default:
            kind = .unknown
        }
    }

    /// Actions de Main / Battle Phase, regroupées par carte.
    var actionsByCard: [String: [DuelAction]] {
        switch kind {
        case .idle(let actions, _, _), .battle(let actions, _, _):
            Dictionary(grouping: actions, by: \.card.key)
        default:
            [:]
        }
    }

    var placeableZones: Set<String> {
        if case .place(let zones, _, _) = kind { return Set(zones.map(\.key)) }
        return []
    }
}

/// Événement du journal.
nonisolated struct DuelEvent: Decodable, Hashable, Sendable, Identifiable {
    nonisolated enum Kind: Hashable, Sendable {
        case turn(player: Int)
        case phase(DuelPhase)
        case draw(player: Int, count: Int, codes: [Int])
        case summon(player: Int, code: Int, how: String)
        case set(player: Int)
        case activate(player: Int, code: Int, link: Int, description: String?)
        case chainNegated(link: Int)
        case move(code: Int, from: DuelLocation, to: DuelLocation)
        case attack(code: Int, target: Int?)
        case damage(player: Int, amount: Int, cost: Bool)
        case recover(player: Int, amount: Int)
        case coin([Bool])
        case dice([Int])
        case win(winner: Int?)
        case unknown
    }

    let seq: Int
    let turn: Int
    let kind: Kind
    var id: Int { seq }

    private enum Keys: String, CodingKey {
        case seq, turn, kind, player, phase, count, codes, code, how, chainLink, description, from, to, target
        case amount, cost, results, winner
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        seq = try c.decode(Int.self, forKey: .seq)
        turn = try c.decode(Int.self, forKey: .turn)
        let player = (try? c.decodeIfPresent(Int.self, forKey: .player)) ?? 0
        let code = (try? c.decodeIfPresent(Int.self, forKey: .code)) ?? 0
        // Un événement inattendu ne doit pas empêcher d'afficher tout le duel
        do {
            kind = try Self.decodeKind(c, player: player, code: code)
        } catch {
            kind = .unknown
        }
    }

    private static func decodeKind(_ c: KeyedDecodingContainer<Keys>, player: Int, code: Int) throws -> Kind {
        let kind: Kind
        switch try c.decode(String.self, forKey: .kind) {
        case "TURN": kind = .turn(player: player)
        case "PHASE": kind = .phase(try c.decode(DuelPhase.self, forKey: .phase))
        case "DRAW":
            kind = .draw(player: player, count: try c.decode(Int.self, forKey: .count), codes: try c.decode([Int].self, forKey: .codes))
        case "SUMMON": kind = .summon(player: player, code: code, how: try c.decode(String.self, forKey: .how))
        case "SET": kind = .set(player: player)
        case "ACTIVATE":
            kind = .activate(
                player: player, code: code, link: try c.decode(Int.self, forKey: .chainLink),
                description: try c.decodeIfPresent(String.self, forKey: .description))
        case "CHAIN_NEGATED": kind = .chainNegated(link: try c.decode(Int.self, forKey: .chainLink))
        case "MOVE":
            kind = .move(code: code, from: try c.decode(DuelLocation.self, forKey: .from), to: try c.decode(DuelLocation.self, forKey: .to))
        case "ATTACK": kind = .attack(code: code, target: try c.decodeIfPresent(Int.self, forKey: .target))
        case "DAMAGE":
            kind = .damage(player: player, amount: try c.decode(Int.self, forKey: .amount), cost: try c.decode(Bool.self, forKey: .cost))
        case "RECOVER": kind = .recover(player: player, amount: try c.decode(Int.self, forKey: .amount))
        case "COIN": kind = .coin(try c.decode([Bool].self, forKey: .results))
        case "DICE": kind = .dice(try c.decode([Int].self, forKey: .results))
        case "WIN": kind = .win(winner: try c.decodeIfPresent(Int.self, forKey: .winner))
        default: kind = .unknown
        }
        return kind
    }
}

nonisolated struct DuelChainLink: Decodable, Hashable, Sendable {
    let card: DuelCardRef
    let description: String?
}

nonisolated struct DuelResult: Decodable, Hashable, Sendable {
    let winner: Int?
    let reason: String?
}

nonisolated struct DuelState: Decodable, Sendable {
    let id: String
    let turn: Int
    let turnPlayer: Int
    let phase: DuelPhase
    let players: [DuelPlayer]
    let chain: [DuelChainLink]
    let prompt: DuelPrompt?
    let events: [DuelEvent]
    let cards: [String: CardSummary]
    let opponentControl: DuelOpponentControl
    let chainPrompts: DuelChainPrompts
    let finished: DuelResult?

    var me: DuelPlayer { players[0] }
    var opponent: DuelPlayer { players[1] }
}

nonisolated struct DuelEngineStatus: Decodable, Sendable {
    let ready: Bool
    let downloading: Bool
    let cards: Int
    let scripts: Int
    let error: String?
}

// MARK: - Réponses

/// Réponse à l'invite en cours (champs absents = null côté API : passer, annuler, terminer).
nonisolated struct DuelAnswer: Encodable, Sendable {
    nonisolated struct Action: Encodable, Sendable {
        let kind: String
        let index: Int
    }

    var action: Action?
    var phase: String?
    var index: Int?
    var indices: [Int]?
    var yes: Bool?
    var zones: [DuelZone]?
    var position: DuelPosition?
    var values: [String]?
    var cardId: Int?
    var order: [Int]?
}

nonisolated struct DuelResponseBody: Encodable, Sendable {
    let promptId: Int
    let answer: DuelAnswer

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(promptId, forKey: .promptId)
        try answer.encode(to: encoder)
    }

    private enum CodingKeys: String, CodingKey { case promptId }
}

nonisolated struct DuelSettingsBody: Encodable, Sendable {
    let chainPrompts: DuelChainPrompts
}
