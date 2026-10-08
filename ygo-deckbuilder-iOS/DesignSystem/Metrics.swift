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

/// Rayons des coins (continus). Une pochette est découpée, pas moussée.
enum Radius {
    /// Visuel de carte Yu-Gi-Oh!
    static let card: CGFloat = 4
    /// Petites surfaces : pochettes, champs
    static let s: CGFloat = 5
    /// Cartes de contenu
    static let m: CGFloat = 8
    /// Panneaux flottants en verre — le système garde sa rondeur
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

    /**
     Une pochette : un creux dans la page, jamais une surface posée dessus. L'ombre est
     *interne* — c'est ce qui distingue un emplacement vide d'une carte flottante, et c'est le
     geste central de la direction.
     */
    func pocket(padding: CGFloat = 2, radius: CGFloat = Radius.s, visible: Bool = true) -> some View {
        self
            .padding(padding)
            .background {
                if visible {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Theme.pocket.shadow(.inner(color: .black.opacity(0.5), radius: 2, y: 1)))
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(Theme.pocketEdge.opacity(0.08), lineWidth: 0.5)
                        }
                }
            }
    }
}

/// Titre de section : icône teintée, titre, et un élément optionnel à droite.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var systemImage: String?
    /// Une précision sous le titre : le titre nomme, l'indice précise. Deux niveaux de
    /// lecture plutôt qu'un seul titre à rallonge coupé d'un point médian.
    var hint: String?
    /// Le filet qui tient la section. Faux quand le titre sert d'étiquette à autre chose
    /// (le libellé d'un `DisclosureGroup`), où un trait sous le chevron ne veut rien dire.
    var ruled = true
    @ViewBuilder var trailing: () -> Trailing

    init(
        _ title: String, systemImage: String? = nil, hint: String? = nil, ruled: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.hint = hint
        self.ruled = ruled
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: Spacing.s)
                trailing()
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, ruled ? Spacing.xs : 0)
        .overlay(alignment: .bottom) { if ruled { Divider() } }
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, systemImage: String? = nil, hint: String? = nil, ruled: Bool = true) {
        self.init(title, systemImage: systemImage, hint: hint, ruled: ruled) { EmptyView() }
    }
}
