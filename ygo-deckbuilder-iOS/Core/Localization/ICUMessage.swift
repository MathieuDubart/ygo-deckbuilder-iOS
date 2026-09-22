import Foundation

/// Sous-ensemble du format ICU MessageFormat utilisé par les messages du web (next-intl) :
/// `{arg}`, `{n, plural, =0 {…} one {# carte} other {# cartes}}`, `{x, select, a {…} other {…}}`,
/// balises `<strong>…</strong>` et apostrophes d'échappement. Pur, sans dépendance à l'UI.
nonisolated struct ICUMessage: Sendable {
    /// Morceau de texte formaté et les balises qui l'entourent (["strong"], ["link"]…).
    nonisolated struct Run: Equatable, Sendable {
        var text: String
        var tags: [String]
    }

    nonisolated indirect enum Node: Sendable {
        case text(String)
        case argument(String)
        case pound
        case plural(argument: String, offset: Double, cases: [(String, [Node])])
        case select(argument: String, cases: [(String, [Node])])
        case tag(String, [Node])
    }

    let nodes: [Node]

    init(_ source: String) {
        var parser = ICUParser(Array(source))
        nodes = parser.parseMessage(inPlural: false)
    }

    /// Texte brut (balises retirées).
    func format(_ args: [String: any Sendable], locale: Locale) -> String {
        runs(args, locale: locale).map(\.text).joined()
    }

    func runs(_ args: [String: any Sendable], locale: Locale) -> [Run] {
        var out: [Run] = []
        ICURenderer(args: args, locale: locale).render(nodes, tags: [], pound: nil, into: &out)
        return out
    }
}

// MARK: - Analyse

nonisolated private struct ICUParser {
    let chars: [Character]
    var i = 0

    init(_ chars: [Character]) { self.chars = chars }

    var atEnd: Bool { i >= chars.count }
    func peek(_ offset: Int = 0) -> Character? {
        i + offset < chars.count ? chars[i + offset] : nil
    }

    mutating func skipSpaces() {
        while let c = peek(), c.isWhitespace { i += 1 }
    }

    /// Jusqu'à `}` (fin d'un cas de pluriel), `</` (fin de balise) ou la fin du texte.
    mutating func parseMessage(inPlural: Bool, closingTag: String? = nil) -> [ICUMessage.Node] {
        var nodes: [ICUMessage.Node] = []
        var buffer = ""
        func flush() {
            if !buffer.isEmpty { nodes.append(.text(buffer)); buffer = "" }
        }

        while let c = peek() {
            if c == "}" { break }
            if c == "<", peek(1) == "/" {
                if closingTag != nil { break }
                buffer.append(c); i += 1; continue
            }
            switch c {
            case "'":
                buffer += readQuoted(inPlural: inPlural)
            case "{":
                flush()
                if let node = parseArgument() { nodes.append(node) }
            case "#" where inPlural:
                flush()
                nodes.append(.pound)
                i += 1
            case "<":
                if let node = parseTag(inPlural: inPlural) {
                    flush()
                    nodes.append(node)
                } else {
                    buffer.append(c); i += 1
                }
            default:
                buffer.append(c); i += 1
            }
        }
        flush()
        return nodes
    }

    /// `''` → `'` ; `'{…}'` → texte littéral ; sinon l'apostrophe est un caractère normal.
    mutating func readQuoted(inPlural: Bool) -> String {
        i += 1  // apostrophe
        guard let next = peek() else { return "'" }
        if next == "'" { i += 1; return "'" }
        let special: Set<Character> = inPlural ? ["{", "}", "#", "<"] : ["{", "}", "<"]
        guard special.contains(next) else { return "'" }
        var out = ""
        while let c = peek() {
            i += 1
            if c == "'" {
                if peek() == "'" { out.append("'"); i += 1; continue }
                break
            }
            out.append(c)
        }
        return out
    }

    mutating func readIdentifier() -> String {
        var s = ""
        while let c = peek(), c.isLetter || c.isNumber || c == "_" || c == "-" || c == "=" || c == ":" || c == "." {
            s.append(c); i += 1
        }
        return s
    }

    mutating func parseArgument() -> ICUMessage.Node? {
        i += 1  // {
        skipSpaces()
        let name = readIdentifier()
        skipSpaces()
        if peek() == "}" { i += 1; return .argument(name) }
        guard peek() == "," else { skipToClosingBrace(); return .argument(name) }
        i += 1
        skipSpaces()
        let type = readIdentifier()
        skipSpaces()
        switch type {
        case "plural", "selectordinal":
            guard peek() == "," else { skipToClosingBrace(); return .argument(name) }
            i += 1
            var offset = 0.0
            skipSpaces()
            if chars[i...].starts(with: Array("offset:")) {
                i += 7
                offset = Double(readIdentifier()) ?? 0
            }
            return .plural(argument: name, offset: offset, cases: parseCases(inPlural: true))
        case "select":
            guard peek() == "," else { skipToClosingBrace(); return .argument(name) }
            i += 1
            return .select(argument: name, cases: parseCases(inPlural: false))
        default:
            // number, date… : formatage simple de la valeur
            skipToClosingBrace()
            return .argument(name)
        }
    }

    mutating func parseCases(inPlural: Bool) -> [(String, [ICUMessage.Node])] {
        var cases: [(String, [ICUMessage.Node])] = []
        while true {
            skipSpaces()
            guard let c = peek() else { break }
            if c == "}" { i += 1; break }
            let key = readIdentifier()
            skipSpaces()
            guard !key.isEmpty, peek() == "{" else { skipToClosingBrace(); break }
            i += 1
            let body = parseMessage(inPlural: inPlural)
            if peek() == "}" { i += 1 }
            cases.append((key, body))
        }
        return cases
    }

    mutating func skipToClosingBrace() {
        var depth = 0
        while let c = peek() {
            i += 1
            if c == "{" { depth += 1 }
            if c == "}" {
                if depth == 0 { return }
                depth -= 1
            }
        }
    }

    /// `<strong>…</strong>` ou `<br/>`. Renvoie nil si ce n'est pas une balise (ex. « a < b »).
    mutating func parseTag(inPlural: Bool) -> ICUMessage.Node? {
        let start = i
        i += 1
        var name = ""
        while let c = peek(), c.isLetter || c.isNumber || c == "_" || c == "-" {
            name.append(c); i += 1
        }
        guard !name.isEmpty else { i = start; return nil }
        if peek() == "/", peek(1) == ">" {
            i += 2
            return .tag(name, [])
        }
        guard peek() == ">" else { i = start; return nil }
        i += 1
        let children = parseMessage(inPlural: inPlural, closingTag: name)
        // </name>
        if peek() == "<", peek(1) == "/" {
            i += 2
            while let c = peek(), c != ">" { i += 1 }
            if peek() == ">" { i += 1 }
        }
        return .tag(name, children)
    }
}

// MARK: - Rendu

nonisolated private struct ICURenderer {
    let args: [String: any Sendable]
    let locale: Locale

    func render(_ nodes: [ICUMessage.Node], tags: [String], pound: Double?, into out: inout [ICUMessage.Run]) {
        for node in nodes {
            switch node {
            case .text(let s):
                append(s, tags: tags, into: &out)
            case .argument(let name):
                append(string(args[name]), tags: tags, into: &out)
            case .pound:
                append(pound.map(formatNumber) ?? "#", tags: tags, into: &out)
            case .plural(let name, let offset, let cases):
                let value = number(args[name]) ?? 0
                let n = value - offset
                let chosen =
                    cases.first { $0.0 == "=\(format(value))" }?.1
                    ?? cases.first { $0.0 == pluralCategory(n) }?.1
                    ?? cases.first { $0.0 == "other" }?.1
                    ?? []
                render(chosen, tags: tags, pound: n, into: &out)
            case .select(let name, let cases):
                let key = string(args[name])
                let chosen = cases.first { $0.0 == key }?.1 ?? cases.first { $0.0 == "other" }?.1 ?? []
                render(chosen, tags: tags, pound: pound, into: &out)
            case .tag(let name, let children):
                render(children, tags: tags + [name], pound: pound, into: &out)
            }
        }
    }

    func append(_ text: String, tags: [String], into out: inout [ICUMessage.Run]) {
        guard !text.isEmpty else { return }
        if let last = out.last, last.tags == tags {
            out[out.count - 1].text += text
        } else {
            out.append(.init(text: text, tags: tags))
        }
    }

    func number(_ value: (any Sendable)?) -> Double? {
        switch value {
        case let v as Int: Double(v)
        case let v as Double: v
        case let v as Float: Double(v)
        case let v as String: Double(v)
        default: nil
        }
    }

    func string(_ value: (any Sendable)?) -> String {
        switch value {
        case nil: ""
        case let v as String: v
        case let v as Int: formatNumber(Double(v))
        case let v as Double: formatNumber(v)
        default: String(describing: value!)
        }
    }

    /// Nombre sans séparateurs pour la comparaison `=0`.
    func format(_ n: Double) -> String {
        n.rounded() == n ? String(Int(n)) : String(n)
    }

    func formatNumber(_ n: Double) -> String {
        n.formatted(.number.locale(locale))
    }

    /// Règles CLDR des langues de l'app (cardinaux).
    func pluralCategory(_ n: Double) -> String {
        let isInteger = n.rounded() == n
        switch locale.language.languageCode?.identifier ?? "en" {
        case "fr", "pt":
            // i = 0,1 → one
            return n >= 0 && n < 2 ? "one" : "other"
        default:
            // en, de, it : i = 1 et v = 0 → one
            return isInteger && n == 1 ? "one" : "other"
        }
    }
}
