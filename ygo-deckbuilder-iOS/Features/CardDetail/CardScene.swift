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

    /// Les UV de `generatePlane` ont leur origine en bas : sans ça, la carte est tête en bas.
    static let flipsTextureVertically = true

    /// Rayon des coins, en unités de largeur de carte (3,2 mm sur une vraie carte).
    private static let cornerRadius: Float = 0.058
    /// Retrait de la tranche, pour que ses coins carrés restent cachés derrière les coins
    /// arrondis de la face et du dos.
    private static let edgeInset: Float = 0.019

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

    /// Nom de l'enfant qui porte la face avant, pour retrouver son matériau.
    private static let frontName = "card-front"

    /// La carte : deux plans aux coins arrondis (face et dos) encadrant une tranche de carton.
    /// Les coins sont dans la géométrie, pas découpés au shader : ils sont donc lissés, et les
    /// plans ont des UV propres sur 0…1, ce que les faces d'une boîte ne garantissent pas.
    static func makeCard(front: CGImage, back: CGImage?, foil: CardFoil) async -> Entity? {
        guard let library else { return nil }
        guard let frontMaterial = await material(
            shader: "cardFrontSurface", image: front, settings: settings(for: foil), library: library)
        else { return nil }

        let face = MeshResource.generatePlane(
            width: width, height: height, cornerRadius: cornerRadius * width)

        let root = Entity()

        let frontEntity = ModelEntity(mesh: face, materials: [frontMaterial])
        frontEntity.name = frontName
        frontEntity.position.z = thickness / 2
        root.addChild(frontEntity)

        var backMaterial: any Material = SimpleMaterial(
            color: UIColor(white: 0.1, alpha: 1), roughness: 0.6, isMetallic: false)
        if let back, let textured = await material(
            shader: "cardBackSurface", image: back, settings: settings(for: .none), library: library) {
            backMaterial = textured
        }
        let backEntity = ModelEntity(mesh: face, materials: [backMaterial])
        backEntity.position.z = -thickness / 2
        // Demi-tour : le plan regarde vers l'arrière, et sa texture est remise à l'endroit
        backEntity.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        root.addChild(backEntity)

        // La tranche : du carton blanc cassé, en retrait pour que ses coins ne dépassent pas
        let edge = ModelEntity(
            mesh: .generateBox(
                width: width - edgeInset * width * 2,
                height: height - edgeInset * width * 2,
                depth: thickness),
            materials: [SimpleMaterial(
                color: UIColor(white: 0.93, alpha: 1), roughness: 0.85, isMetallic: false)])
        root.addChild(edge)

        return root
    }

    /// Change la rareté affichée sans reconstruire la carte.
    static func applyFoil(_ foil: CardFoil, to card: Entity?) {
        guard let front = card?.findEntity(named: frontName) as? ModelEntity,
              var material = front.model?.materials.first as? CustomMaterial
        else { return }
        material.custom.value = settings(for: foil)
        front.model?.materials[0] = material
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
            material.faceCulling = .back
            return material
        } catch {
            return nil
        }
    }
}
