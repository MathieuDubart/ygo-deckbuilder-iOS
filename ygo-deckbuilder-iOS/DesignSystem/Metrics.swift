import SwiftUI

/// Échelle d'espacements : toujours ces valeurs, jamais de chiffre au hasard dans les vues.
enum Spacing {
    /// Entre une icône et son texte, dans une puce
    static let xxs: CGFloat = 4
    /// Entre éléments d'une même ligne (puces, badges)
    static let xs: CGFloat = 6
    /// Entre lignes d'un même bloc
    static let s: CGFloat = 8
    /// Entre éléments d'une carte
    static let m: CGFloat = 12
    /// Marges intérieures des cartes, gouttière des grilles
    static let l: CGFloat = 16
    /// Entre blocs d'un écran
    static let xl: CGFloat = 24
    /// Entre grandes sections d'un écran
    static let section: CGFloat = 36
}

/// Rayons des coins (continus).
enum Radius {
    /// Visuel de carte Yu-Gi-Oh!
    static let card: CGFloat = 6
    /// Petites surfaces : tuiles de chiffres, champs
    static let s: CGFloat = 12
    /// Cartes de contenu
    static let m: CGFloat = 20
    /// Panneaux flottants en verre
    static let l: CGFloat = 28
}

/// Largeurs minimales des grilles adaptatives.
enum GridWidth {
    /// Cartes dans une zone de deck (5 par ligne sur iPhone)
    static let compactCard: CGFloat = 64
    /// Cartes du catalogue, du picker (3 à 4 par ligne sur iPhone)
    static let card: CGFloat = 96
    /// Visuels de produits (2 par ligne sur iPhone)
    static let product: CGFloat = 150
    /// Cartes de suggestion (1 par ligne sur iPhone, 2-3 sur iPad)
    static let panel: CGFloat = 320
}

extension View {
    /// Surface de contenu : marges intérieures, fond secondaire, coins arrondis.
    func surface(padding: CGFloat = Spacing.l, radius: CGFloat = Radius.m) -> some View {
        self
            .padding(padding)
            .background(.background.secondary, in: .rect(cornerRadius: radius, style: .continuous))
    }

    /// Surface discrète (tuiles, encarts) sur fond de remplissage.
    func tileSurface(padding: CGFloat = Spacing.m, radius: CGFloat = Radius.s) -> some View {
        self
            .padding(padding)
            .background(.fill.quaternary, in: .rect(cornerRadius: radius, style: .continuous))
    }
}

/// Titre de section : icône teintée, titre, et un élément optionnel à droite.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, systemImage: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .imageScale(.medium)
            }
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: Spacing.s)
            trailing()
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, systemImage: String? = nil) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}
