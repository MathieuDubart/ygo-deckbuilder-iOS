import SwiftUI
import UIKit

/**
 Couleurs de l'app, alignées sur le web : le classeur du collectionneur.

 Les cartes sont la seule couleur. Le chrome tient en noir chaud (le carton) et en blanc os
 (l'étiquette collée sur l'intercalaire, qui est aussi la couleur d'accent de l'app). L'or ne
 décore pas : il se mérite — rareté premium et extension bouclée, rien d'autre.
 */
enum Theme {
    /// Une pochette : toujours plus sombre que sa page. Elle doit creuser aussi bien sur le
    /// fond système groupé que sur le noir pur, d'où le liseré de `pocketEdge` qui l'accompagne
    /// — en sombre, l'écart de valeur seul ne suffirait pas.
    static let pocket = adaptive(light: (0.898, 0.886, 0.859), dark: (0.035, 0.031, 0.027))
    /// Le liseré d'une pochette : le pli du carton, pas une bordure.
    static let pocketEdge = adaptive(light: (0.000, 0.000, 0.000), dark: (1.000, 1.000, 1.000))
    /// L'encre qu'on pose SUR l'accent (os en sombre, presque noir en clair) : son inverse.
    static let accentInk = adaptive(light: (0.969, 0.961, 0.945), dark: (0.110, 0.102, 0.090))
    /// L'or, et lui seul, pour ce qui se mérite.
    static let gold = adaptive(light: (0.667, 0.502, 0.145), dark: (0.910, 0.760, 0.360))

    private static func adaptive(
        light: (Double, Double, Double), dark: (Double, Double, Double)
    ) -> Color {
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    static let success = Color(red: 0.30, green: 0.75, blue: 0.52)
    static let warning = Color(red: 0.93, green: 0.66, blue: 0.25)
    static let danger = Color(red: 0.92, green: 0.36, blue: 0.33)

    static let monster = Color(red: 0.84, green: 0.55, blue: 0.27)
    static let spell = Color(red: 0.16, green: 0.62, blue: 0.56)
    static let trap = Color(red: 0.74, green: 0.30, blue: 0.53)
    static let extra = Color(red: 0.49, green: 0.41, blue: 0.84)

    /// Ratio d'une carte Yu-Gi-Oh! (≈ 421 × 614).
    static let cardAspect: CGFloat = 421.0 / 614.0

    static func color(for card: CardSummary) -> Color {
        if card.isExtraDeck { return extra }
        switch card.category {
        case .monster: return monster
        case .spell: return spell
        case .trap: return trap
        case .skill, .token: return .gray
        }
    }

    static func coverageColor(_ value: Double) -> Color {
        // Complet = or, c'est le seul endroit avec la rareté où il apparaît
        value >= 1 ? gold : value >= 0.6 ? success : value >= 0.3 ? warning : danger
    }

    static func scoreColor(_ score: Int) -> Color {
        score >= 70 ? success : score >= 50 ? warning : danger
    }

    /**
     Une rareté mérite-t-elle l'or ? Les noms viennent du catalogue en anglais et ne sont pas
     normalisés (« Ultra Rare », « Quarter Century Secret Rare »…), d'où une détection par
     mot-clé plutôt qu'une liste fermée, périmée à la prochaine extension.
     */
    static func isPremiumRarity(_ rarity: String?) -> Bool {
        guard let rarity else { return false }
        let value = rarity.lowercased()
        return ["ultra", "secret", "ultimate", "ghost", "starlight", "collector", "platinum",
                "gold", "prismatic", "serial"].contains { value.contains($0) }
    }
}

extension View {
    /**
     Un code d'extension, une quantité, un prix : condensé et tabulaire, jamais à chasse fixe.
     Les codes sont imprimés en condensé sur les vraies cartes, et la largeur de SF Pro donne
     exactement ça sans embarquer de police.
     */
    func codeStyle(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> some View {
        font(.system(size: size, weight: weight).width(.condensed).monospacedDigit())
    }
}

/// Petite étiquette en capsule.
struct Pill: View {
    let text: String
    var tint: Color = .secondary
    var systemImage: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .labelStyle(PillLabelStyle(hasIcon: systemImage != nil))
        .font(.system(size: 11, weight: .medium).width(.condensed))
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 3, style: .continuous))
        .fixedSize()
    }
}

private struct PillLabelStyle: LabelStyle {
    let hasIcon: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            if hasIcon { configuration.icon.imageScale(.small) }
            configuration.title
        }
    }
}

/// Chiffre clé (stats de la collection, résumé d'un deck généré…).
struct StatTile: View {
    let label: String
    let value: String
    var tint: Color = .primary
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.xxs) {
                if let systemImage { Image(systemName: systemImage).font(.caption) }
                Text(value)
                    .font(.system(size: 22, weight: .semibold).width(.condensed).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xs)
    }
}

/// Part de la liste déjà possédée, en anneau.
struct CoverageRing: View {
    let value: Double
    var size: CGFloat = 52
    var lineWidth: CGFloat = 5

    var body: some View {
        let color = Theme.coverageColor(value)
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(L10n.shared.percent(value))
                .font(.system(size: size * 0.24, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(t("suggestions.meta.card.coverage"))
        .accessibilityValue(L10n.shared.percent(value))
    }
}

/// Note de solidité (0–100).
struct ScoreBadge: View {
    let score: Int

    var body: some View {
        let color = Theme.scoreColor(score)
        VStack(spacing: 0) {
            Text("\(score)")
                .font(.title3.bold().width(.condensed).monospacedDigit())
            Text(t("suggestions.score.label"))
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(color.opacity(0.4)))
        .accessibilityElement(children: .combine)
        .accessibilityHint(t("suggestions.score.hint"))
    }
}

/// Critères de la note, en mots.
struct ScoreBreakdown: View {
    let score: DeckScore

    private var items: [(key: String, value: String)] {
        let l = L10n.shared
        var out: [(String, String)] = [("engine", l.percent(score.engineShare))]
        if let synergy = score.synergy {
            out.append(("synergy", l.percent(synergy)))
            out.append(("starters", l.number(score.starters ?? 0)))
        }
        out.append(("staples", l.number(score.staples)))
        out.append(("consistency", l.percent(score.consistency)))
        out.append(("filler", l.percent(score.fillerShare)))
        return out.map { (key: $0.0, value: $0.1) }
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3), spacing: Spacing.xs) {
            ForEach(items, id: \.key) { item in
                VStack(spacing: 2) {
                    Text(t("suggestions.score.criteria.\(item.key).label"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(item.value)
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s)
                .background(.fill.quaternary, in: .rect(cornerRadius: Radius.card, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityHint(t("suggestions.score.criteria.\(item.key).hint"))
            }
        }
    }
}

/// Puce de filtre en verre (active = teintée de l'accent).
struct FilterChip<Content: View>: View {
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder var label: () -> Content

    var body: some View {
        Button(action: action) {
            ChipLabel(isOn: isOn, label: label)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension FilterChip where Content == Label<Text, Image> {
    init(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) {
        self.init(isOn: isOn, action: action) { Label(title, systemImage: systemImage) }
    }
}

extension FilterChip where Content == Text {
    init(_ title: String, isOn: Bool, action: @escaping () -> Void) {
        self.init(isOn: isOn, action: action) { Text(title) }
    }
}

/**
 Contre quoi un deck tient, et contre quoi il souffre.

 L'ordre est celui du serveur, du plus favorable au moins favorable : on lit d'abord ce
 qu'on sait battre. Chaque ligne porte sa raison, parce qu'un verdict sans cause ne se
 corrige pas — « défavorable » n'apprend rien, « trop peu de cartes de main » se joue.
 */
struct MatchupList: View {
    let matchups: [Matchup]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(matchups.enumerated()), id: \.offset) { _, m in
                HStack(alignment: .top, spacing: Spacing.s) {
                    Image(systemName: Self.symbol(m.verdict))
                        .font(.caption)
                        .foregroundStyle(Self.tint(m.verdict))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        // Un nom de deck du meta quand on le connaît, une forme de jeu sinon
                        Text(m.opponent ?? t("decks.matchups.vsStyle",
                                             ["style": t("decks.styles.\(m.against.rawValue)")]))
                            .font(.caption.weight(.medium))
                        Text(t("decks.matchups.reasons.\(m.reason)"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Text(t("decks.matchups.verdicts.\(m.verdict.rawValue)"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Self.tint(m.verdict))
                }
                .padding(.vertical, 2)
            }
        }
    }

    private static func symbol(_ v: MatchupVerdict) -> String {
        switch v {
        case .good: "hand.thumbsup.fill"
        case .even: "minus"
        case .bad: "hand.thumbsdown.fill"
        }
    }

    private static func tint(_ v: MatchupVerdict) -> Color {
        switch v {
        case .good: Theme.success
        case .even: .secondary
        case .bad: Theme.warning
        }
    }
}

/// La force complète d'un deck : sa note, sa forme, ses pronostics.
struct DeckStrengthPanel: View {
    let strength: DeckStrength?

    var body: some View {
        if let strength {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(alignment: .top, spacing: Spacing.m) {
                    ScoreBadge(score: strength.score.score)
                    VStack(alignment: .leading, spacing: 2) {
                        Pill(text: t("decks.styles.\(strength.profile.style.rawValue)"),
                             tint: .accentColor)
                        Text(t("decks.styleHints.\(strength.profile.style.rawValue)"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                ScoreBreakdown(score: strength.score)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    SectionHeader(t("decks.matchups.title"), hint: t("decks.matchups.hint"))
                    MatchupList(matchups: strength.matchups)
                }
            }
        } else {
            Text(t("decks.matchups.none"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
