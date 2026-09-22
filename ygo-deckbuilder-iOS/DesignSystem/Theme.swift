import SwiftUI

/// Couleurs de l'app (alignées sur la palette du web). L'accent doré vient de l'asset AccentColor.
enum Theme {
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
        value >= 1 ? success : value >= 0.6 ? .accentColor : value >= 0.3 ? warning : danger
    }

    static func scoreColor(_ score: Int) -> Color {
        score >= 70 ? success : score >= 50 ? .accentColor : warning
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
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: .capsule)
    }
}

private struct PillLabelStyle: LabelStyle {
    let hasIcon: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            if hasIcon { configuration.icon }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).font(.caption) }
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.quaternary, in: .rect(cornerRadius: 14))
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
                .font(.title3.bold().monospacedDigit())
            Text(t("suggestions.score.label"))
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.5)))
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
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
                .padding(.vertical, 6)
                .background(.fill.quaternary, in: .rect(cornerRadius: 8))
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
            label()
                .lineLimit(1)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(isOn ? .regular.tint(.accentColor.opacity(0.25)).interactive() : .regular.interactive(), in: .capsule)
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
