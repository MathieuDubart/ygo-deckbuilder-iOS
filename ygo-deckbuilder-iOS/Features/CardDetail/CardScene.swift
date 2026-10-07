import Metal
import RealityKit
import UIKit

/// Construction de l'objet « carte » : un parallélépipède aux proportions d'une vraie carte
/// (59 × 86 × 0,33 mm, à l'échelle 10 pour rester à des distances confortables en mètres),
/// face avant et dos texturés, tranche en carton. La dorure est un `CustomMaterial` dont le
/// shader est dans `CardFoil.metal`.
@MainActor
enum CardScene {
    static let width: Float = 0.59
    static let height: Float = 0.86
    /// Une carte fait environ 0,33 mm d'épaisseur.
    static let thickness: Float = 0.0033

    /// Dos officiel, servi par le même catalogue que les faces (donc par l'optimiseur du
    /// serveur, comme le reste des visuels). S'il est indisponible, la tranche fait office
    /// de dos et on garde un carton neutre.
    static let backImageURL = URL(string: "https://images.ygoprodeck.com/images/cards/back.jpg")

    /// À passer à `true` si la carte apparaît tête en bas : l'orientation verticale des UV de
    /// `generateBox` n'est pas documentée, et c'est le seul réglage à changer si c'est le cas.
    static let flipsTextureVertically = false

    private static let library: MTLLibrary? = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary()

    /// `true` si l'appareil peut rendre la carte en 3D (shaders compilés, Metal disponible).
    static var isAvailable: Bool { library != nil }

    static func image(at url: URL?, width: ImagePipeline.Width = .large) async -> CGImage? {
        guard let url else { return nil }
        let resolved = ImagePipeline.shared.url(for: url, width: width)
        return await ImagePipeline.shared.image(for: resolved)?.cgImage
    }

    static func backImage() async -> CGImage? {
        await image(at: backImageURL, width: .medium)
    }

    static func makeCard(front: CGImage, back: CGImage?, foil: CardFoil) async -> ModelEntity? {
        guard let library else { return nil }
        let mesh = MeshResource.generateBox(
            width: width, height: height, depth: thickness, splitFaces: true)
        guard let frontMaterial = await material(
            shader: "cardFrontSurface", image: front, settings: settings(for: foil), library: library)
        else { return nil }

        // Le carton vu par la tranche : blanc cassé et mat
        let edge = SimpleMaterial(
            color: UIColor(white: 0.93, alpha: 1), roughness: 0.8, isMetallic: false)

        var backMaterial: any Material = SimpleMaterial(
            color: UIColor(white: 0.12, alpha: 1), roughness: 0.6, isMetallic: false)
        if let back, let textured = await material(
            shader: "cardBackSurface", image: back, settings: settings(for: .none), library: library) {
            backMaterial = textured
        }

        // generateBox(splitFaces:) : 0 avant (+Z), 1 haut, 2 arrière (-Z), 3 bas, 4 droite, 5 gauche
        return ModelEntity(
            mesh: mesh,
            materials: [frontMaterial, edge, backMaterial, edge, edge, edge])
    }

    /// Change la rareté affichée sans reconstruire la carte.
    static func applyFoil(_ foil: CardFoil, to entity: ModelEntity?) {
        guard let entity,
              var material = entity.model?.materials.first as? CustomMaterial
        else { return }
        material.custom.value = settings(for: foil)
        entity.model?.materials[0] = material
    }

    /// x = traitement, y = force, z = UV retournés, w = libre.
    private static func settings(for foil: CardFoil) -> SIMD4<Float> {
        SIMD4<Float>(
            Float(foil.rawValue), foil.strength, flipsTextureVertically ? 1 : 0, 0)
    }

    private static func material(
        shader: String, image: CGImage, settings: SIMD4<Float>, library: MTLLibrary
    ) async -> CustomMaterial? {
        do {
            let texture = try await TextureResource(
                image: image, withName: nil, options: .init(semantic: .color))
            var material = try CustomMaterial(
                surfaceShader: .init(named: shader, in: library),
                geometryModifier: nil,
                lightingModel: .lit)
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.custom.value = settings
            // Les coins arrondis sont découpés par le shader
            material.opacityThreshold = 0.5
            material.faceCulling = .back
            return material
        } catch {
            return nil
        }
    }
}
