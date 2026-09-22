import Foundation

// Enums métier : alignés sur packages/shared/src/domain/enums.ts (côté web).

nonisolated enum CardCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case monster = "MONSTER", spell = "SPELL", trap = "TRAP", skill = "SKILL", token = "TOKEN"

    /// Ordre d'affichage dans un deck (monstres, magies, pièges).
    var sortOrder: Int {
        switch self {
        case .monster: 0
        case .spell: 1
        case .trap: 2
        case .skill: 3
        case .token: 4
        }
    }
}

nonisolated enum DeckZone: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case main = "MAIN", extra = "EXTRA", side = "SIDE"
    var id: String { rawValue }
}

nonisolated enum DeckFormat: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case tcg = "TCG", ocg = "OCG", goat = "GOAT", edison = "EDISON", casual = "CASUAL"
    var id: String { rawValue }
}

nonisolated enum CardCondition: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case mint = "MINT", nearMint = "NEAR_MINT", excellent = "EXCELLENT", good = "GOOD"
    case lightPlayed = "LIGHT_PLAYED", played = "PLAYED", poor = "POOR"
    var id: String { rawValue }
}

nonisolated enum CardLanguage: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case fr = "FR", en = "EN", de = "DE", it = "IT", es = "ES", pt = "PT", jp = "JP", kr = "KR"
    var id: String { rawValue }
}

nonisolated enum WishlistPriority: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case low = "LOW", medium = "MEDIUM", high = "HIGH"
    var id: String { rawValue }
}

nonisolated enum ProductKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case structure = "STRUCTURE", tin = "TIN", starter = "STARTER", box = "BOX", other = "OTHER"
    var id: String { rawValue }
}

nonisolated enum OfficialDeckKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case structure = "STRUCTURE", starter = "STARTER", box = "BOX"
    var id: String { rawValue }
}

nonisolated enum GenerationMode: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case owned = "OWNED", meta = "META"
    var id: String { rawValue }
}

// Valeurs purement affichées : une valeur inconnue (API plus récente) ne casse pas le décodage.

nonisolated enum GeneratedCardSource: String, Hashable, Sendable, Decodable {
    case core = "CORE", flex = "FLEX", staple = "STAPLE", archetype = "ARCHETYPE"
    case support = "SUPPORT", filler = "FILLER", unknown = "UNKNOWN"

    init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// Origines affichées en étiquette (CORE : pas d'étiquette).
    var isLabeled: Bool { self != .core && self != .unknown }
}

nonisolated enum GuideRole: String, Hashable, Sendable, Decodable {
    case starter = "STARTER", searcher = "SEARCHER", extender = "EXTENDER", handTrap = "HAND_TRAP"
    case interruption = "INTERRUPTION", removal = "REMOVAL", draw = "DRAW", recovery = "RECOVERY"
    case fusionEnabler = "FUSION_ENABLER", ritualEnabler = "RITUAL_ENABLER", boss = "BOSS"
    case unknown = "UNKNOWN"

    init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

nonisolated enum InteractionVerb: String, Hashable, Sendable, Decodable {
    case search = "SEARCH", recover = "RECOVER", specialSummon = "SPECIAL_SUMMON"
    case summonExtra = "SUMMON_EXTRA", sendGY = "SEND_GY", material = "MATERIAL", mention = "MENTION"
    case unknown = "UNKNOWN"

    init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}
