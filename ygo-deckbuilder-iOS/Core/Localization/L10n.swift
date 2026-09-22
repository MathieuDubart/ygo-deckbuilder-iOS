import SwiftUI

/// Langues de l'application (mêmes que le web et l'API).
nonisolated enum AppLocale: String, CaseIterable, Identifiable, Sendable {
    case en, fr, de, it, pt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: "English"
        case .fr: "Français"
        case .de: "Deutsch"
        case .it: "Italiano"
        case .pt: "Português"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Langue des cartes proposée par défaut (ajout à la collection).
    var cardLanguage: CardLanguage { CardLanguage(rawValue: rawValue.uppercased()) ?? .en }

    /// Première langue de la liste gérée par l'app, sinon l'anglais.
    static func best(from identifiers: [String]) -> AppLocale {
        for id in identifiers {
            let code = Locale(identifier: id).language.languageCode?.identifier ?? String(id.prefix(2))
            if let match = AppLocale(rawValue: code.lowercased()) { return match }
        }
        return .en
    }
}

/// Traductions : les messages du web (apps/web/messages, format ICU de next-intl) + un
/// namespace `ios`, fusionnés par scripts/sync-messages.py en Resources/messages.<langue>.json.
/// Clés à points : t("collection.view.title"), t("catalog.count", ["count": 3]).
@Observable
final class L10n {
    static let shared = L10n()

    private static let preferenceKey = "app.locale"

    /// Choix explicite dans les réglages de l'app ; nil = langue du système.
    var preference: AppLocale? {
        didSet {
            UserDefaults.standard.set(preference?.rawValue, forKey: Self.preferenceKey)
            load()
        }
    }

    private(set) var current: AppLocale = .en
    private var messages: [String: String] = [:]
    /// Arbre JSON complet de la langue courante (contenus structurés : règles…)
    @ObservationIgnored private var tree: [String: Any] = [:]
    @ObservationIgnored private var fallbackTree: [String: Any] = [:]
    @ObservationIgnored private var fallback: [String: String] = [:]
    @ObservationIgnored private var compiled: [String: ICUMessage] = [:]
    @ObservationIgnored private let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    @ObservationIgnored private let isoPlain = ISO8601DateFormatter()
    @ObservationIgnored private let isoDay: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private init() {
        preference = UserDefaults.standard.string(forKey: Self.preferenceKey).flatMap(AppLocale.init(rawValue:))
        fallbackTree = Self.readTree(.en)
        fallback = Self.flatten(fallbackTree)
        load()
    }

    var locale: Locale { current.locale }

    private func load() {
        current = preference ?? AppLocale.best(from: Bundle.main.preferredLocalizations + Locale.preferredLanguages)
        tree = current == .en ? fallbackTree : Self.readTree(current)
        messages = current == .en ? fallback : Self.flatten(tree)
        compiled = [:]
    }

    private static func readTree(_ locale: AppLocale) -> [String: Any] {
        guard
            let url = Bundle.main.url(forResource: "messages.\(locale.rawValue)", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    private static func flatten(_ json: [String: Any]) -> [String: String] {
        var flat: [String: String] = [:]
        flatten(json, prefix: "", into: &flat)
        return flat
    }

    private static func flatten(_ object: [String: Any], prefix: String, into out: inout [String: String]) {
        for (key, value) in object {
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let s = value as? String {
                out[path] = s
            } else if let nested = value as? [String: Any] {
                flatten(nested, prefix: path, into: &out)
            }
        }
    }

    private func message(_ key: String) -> ICUMessage? {
        if let m = compiled[key] { return m }
        guard let source = messages[key] ?? fallback[key] else { return nil }
        let m = ICUMessage(source)
        compiled[key] = m
        return m
    }

    /// Contenu structuré (tableaux, objets) décodé tel quel, ex. les sections des règles.
    func raw<T: Decodable>(_ key: String, as type: T.Type = T.self) -> T? {
        func find(_ root: [String: Any]) -> Any? {
            var node: Any? = root
            for part in key.split(separator: ".") {
                node = (node as? [String: Any])?[String(part)]
            }
            return node
        }
        guard let node = find(tree) ?? find(fallbackTree), JSONSerialization.isValidJSONObject(node),
              let data = try? JSONSerialization.data(withJSONObject: node)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func has(_ key: String) -> Bool { messages[key] != nil || fallback[key] != nil }

    /// Texte brut (les balises <strong>… sont retirées).
    func t(_ key: String, _ args: [String: any Sendable] = [:]) -> String {
        guard let m = message(key) else { return key }
        return m.format(args, locale: locale)
    }

    /// Texte enrichi : <strong> en gras, <muted> en secondaire, <link> en couleur d'accent.
    func rich(_ key: String, _ args: [String: any Sendable] = [:]) -> AttributedString {
        guard let m = message(key) else { return AttributedString(key) }
        var out = AttributedString()
        for run in m.runs(args, locale: locale) {
            var part = AttributedString(run.text)
            // <c> / <t> : noms de cartes dans le journal du duel
            if run.tags.contains(where: { $0 == "strong" || $0 == "b" || $0 == "c" || $0 == "t" }) {
                part.inlinePresentationIntent = .stronglyEmphasized
            }
            if run.tags.contains("muted") { part.swiftUI.foregroundColor = Color.secondary }
            if run.tags.contains("link") { part.swiftUI.foregroundColor = Color.accentColor }
            out += part
        }
        return out
    }

    // MARK: - Formats (les prix restent en euros : Cardmarket)

    func price(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.currency(code: "EUR").locale(locale))
    }

    func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// Date ISO de l'API ("2026-09-22T13:42:05.254Z" ou "2016-01-08").
    func date(_ iso: String) -> String {
        guard let d = isoFull.date(from: iso) ?? isoPlain.date(from: iso) ?? isoDay.date(from: iso) else {
            return iso
        }
        return d.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
    }
}

/// Raccourci global : t("common.actions.save").
func t(_ key: String, _ args: [String: any Sendable] = [:]) -> String {
    L10n.shared.t(key, args)
}
