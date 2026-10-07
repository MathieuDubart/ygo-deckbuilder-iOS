import SwiftUI

/// Jauge d'avancement. Le ton suit l'état plutôt que la valeur : complet en vert, entamé en
/// couleur d'accent, rien en gris — on lit l'état sans lire le chiffre.
struct Meter: View {
    let value: Int
    let total: Int
    var height: CGFloat = 6

    private var ratio: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(value) / Double(total))
    }

    private var tint: Color {
        if ratio >= 1 { return Theme.success }
        return ratio > 0 ? .accentColor : .secondary.opacity(0.4)
    }

    var body: some View {
        // Une largeur, pas une mise à l'échelle : `scaleEffect` écraserait aussi les
        // extrémités arrondies, et la jauge deviendrait une lentille sous les 50 %.
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary)
                Capsule().fill(tint).frame(width: geo.size.width * ratio)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(t("ios.releases.meter", ["owned": value, "total": total]))
    }
}

/// Le visuel d'une puce de filtre, sans bouton : utilisable comme étiquette de `Menu`,
/// où un bouton imbriqué ne se comporterait pas correctement.
struct ChipLabel<Content: View>: View {
    let isOn: Bool
    @ViewBuilder var label: () -> Content

    var body: some View {
        label()
            .lineLimit(1)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .padding(.horizontal, Spacing.m + 2)
            .padding(.vertical, Spacing.s)
            .glassEffect(
                isOn ? .regular.tint(.accentColor.opacity(0.25)).interactive() : .regular.interactive(),
                in: .capsule)
    }
}

/// Menu d'une facette : une pastille qui ouvre les valeurs réellement disponibles. Une
/// facette sans valeur ne s'affiche pas — on ne propose jamais un filtre qui ne rendrait
/// rien — sauf si une valeur est déjà choisie : il faut toujours pouvoir la retirer.
struct FacetMenu: View {
    let allLabel: String
    let options: [FacetValue]
    @Binding var selection: String?
    /// Libellé lisible d'une valeur (les énumérations sont traduites par l'appelant).
    var display: (FacetValue) -> String = { $0.display }

    private var current: String? {
        guard let selection else { return nil }
        return options.first { $0.value == selection }.map(display) ?? selection
    }

    var body: some View {
        if !options.isEmpty || selection != nil {
            Menu {
                Picker(allLabel, selection: $selection) {
                    Text(allLabel).tag(String?.none)
                    ForEach(options) { option in
                        // Un effectif de 0 veut dire « non calculé » : on ne l'affiche pas
                        Text(option.count > 0 ? "\(display(option)) (\(option.count))" : display(option))
                            .tag(String?.some(option.value))
                    }
                }
            } label: {
                ChipLabel(isOn: selection != nil) {
                    Label(current ?? allLabel, systemImage: "chevron.down")
                        .labelStyle(TrailingIconLabelStyle())
                }
            }
        }
    }
}

/// Icône après le texte (les menus se lisent « valeur ⌄ »).
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.xxs) {
            configuration.title
            configuration.icon.font(.caption2)
        }
    }
}

/// Bande horizontale de filtres, au-dessus d'une liste. Les puces partagent un seul
/// conteneur de verre : une dizaine de couches indépendantes coûterait cher et rendrait mal.
struct FilterBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer {
                HStack(spacing: Spacing.s) { content() }
            }
            .padding(.horizontal, Spacing.l)
        }
        .padding(.horizontal, -Spacing.l)
    }
}
