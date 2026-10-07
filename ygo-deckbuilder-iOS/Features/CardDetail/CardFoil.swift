import Foundation

/// Traitement de surface d'une impression. Les vraies cartes ne sont pas « brillantes ou
/// pas » : chaque rareté vernit une **zone** précise (le nom seul, l'illustration seule,
/// toute la carte) avec un **motif** précis (lignes diagonales, micro-relief, mosaïque,
/// étoiles…). C'est ce couple zone + motif qui rend le rendu reconnaissable.
nonisolated enum CardFoil: Int, CaseIterable, Identifiable, Sendable {
    /// Aucune dorure : Common, Short Print, Normal Parallel…
    case none = 0
    /// Rare : seul le nom est doré.
    case rareName = 1
    /// Super Rare : seule l'illustration est holographique.
    case superArt = 2
    /// Ultra Rare : illustration holographique + nom doré.
    case ultra = 3
    /// Ultimate Rare : comme l'Ultra, avec l'illustration et le cadre en relief.
    case ultimate = 4
    /// Secret Rare : fines lignes diagonales irisées sur toute la carte.
    case secret = 5
    /// Prismatic / Platinum Secret : mêmes lignes, plus serrées et plus vives.
    case prismatic = 6
    /// Ghost Rare : illustration argentée, presque sans couleur, en relief doux.
    case ghost = 7
    /// Starlight, Collector's, Quarter Century : micro-relief sur toute la carte.
    case starlight = 8
    /// Mosaic : grain carré régulier sur toute la carte.
    case mosaic = 9
    /// Starfoil : semis d'étoiles.
    case starfoil = 10
    /// Shatterfoil : éclats façon verre brisé.
    case shatter = 11
    /// Gold Rare : nom, cadre et contours dorés.
    case gold = 12

    var id: Int { rawValue }

    /// Libellé de rareté YGOPRODeck → traitement. Les raretés les plus spécifiques sont
    /// testées en premier : « Prismatic Secret Rare » contient « secret », « Quarter Century
    /// Secret Rare » aussi, et « Ultimate » contient « ultimate » mais pas « ultra ».
    static func matching(_ rarity: String?) -> CardFoil {
        guard let rarity else { return .none }
        let text = rarity.lowercased()
        switch true {
        case text.contains("starlight"), text.contains("collector"),
             text.contains("quarter century"):
            return .starlight
        case text.contains("ghost"):
            return .ghost
        case text.contains("shatterfoil"):
            return .shatter
        case text.contains("starfoil"):
            return .starfoil
        case text.contains("mosaic"):
            return .mosaic
        case text.contains("prismatic"), text.contains("platinum"):
            return .prismatic
        case text.contains("secret"):
            return .secret
        case text.contains("ultimate"):
            return .ultimate
        case text.contains("gold"):
            return .gold
        case text.contains("ultra"):
            return .ultra
        case text.contains("super"), text.contains("duel terminal"), text.contains("parallel"):
            return .superArt
        case text.contains("rare"):
            return .rareName
        default:
            return .none
        }
    }

    /// Force du reflet, de 0 (mat) à 1. Une Rare brille à peine, une Starlight beaucoup.
    var strength: Float {
        switch self {
        case .none: 0
        case .rareName, .gold: 0.55
        case .superArt, .ghost: 0.7
        case .ultra, .mosaic, .starfoil, .shatter: 0.8
        case .secret, .ultimate: 0.9
        case .prismatic, .starlight: 1
        }
    }
}
