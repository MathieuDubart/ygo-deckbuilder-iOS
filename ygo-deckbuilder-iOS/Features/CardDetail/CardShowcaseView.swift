import RealityKit
import simd
import SwiftUI

/// Orientation visée par la carte. Un abonnement par image l'interpole, ce qui donne du
/// poids à l'objet et rend le retour à plat fluide sans animation SwiftUI. Volontairement
/// hors du système d'observation : `body` ne la lit jamais, seule la boucle de rendu le fait.
final class CardSpin {
    var target = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
}

/// La carte en vrai objet 3D : épaisseur, tranche, dos, et la brillance de sa rareté calculée
/// à partir de l'angle de vue réel. On la tourne au doigt sur 360°, double-tap pour la
/// remettre à plat, tap pour fermer.
struct CardShowcaseView: View {
    let card: CardSummary
    /// Raretés disponibles pour cette carte (une par impression, doublons retirés).
    var rarities: [String] = []
    /// Rareté sélectionnée au départ (celle de l'impression scannée, par exemple).
    var initialRarity: String?

    @Environment(\.dismiss) private var dismiss
    @State private var spin = CardSpin()
    @State private var entity: ModelEntity?
    @State private var rarity: String?
    @State private var resting: CGSize = .zero
    @State private var failed = false

    private var foil: CardFoil { CardFoil.matching(rarity) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { dismiss() }

            if failed || !CardScene.isAvailable {
                ContentUnavailableView(
                    t("ios.card.showcaseFailed"), systemImage: "cube.transparent",
                    description: Text(t("ios.card.showcaseFailedHint")))
                    .foregroundStyle(.white)
            } else {
                scene
                if entity == nil {
                    ProgressView().tint(.white)
                }
            }

            VStack {
                Spacer(minLength: 0)
                if rarities.count > 1 { raritySwitcher }
                Text(t("ios.card.rotateHint"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.l)
        }
        .overlay(alignment: .topTrailing) {
            Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .padding(Spacing.l)
        }
        .statusBarHidden()
        .task { rarity = initialRarity ?? rarities.first }
        .onChange(of: rarity) { CardScene.applyFoil(foil, to: entity) }
    }

    private var scene: some View {
        RealityView { content in
            content.camera = .virtual

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 45
            camera.look(at: .zero, from: SIMD3<Float>(0, 0, 1.95), relativeTo: nil)
            content.add(camera)

            // Une lumière principale en haut à droite, une douce à l'opposé : la dorure a
            // besoin d'un contraste marqué pour que la bande lumineuse se voie.
            for (position, intensity) in [
                (SIMD3<Float>(0.9, 1.1, 1.5), Float(2800)),
                (SIMD3<Float>(-1.3, -0.5, 1.1), Float(1100)),
            ] {
                let light = DirectionalLight()
                light.light.intensity = intensity
                light.look(at: .zero, from: position, relativeTo: nil)
                content.add(light)
            }

            guard let front = await CardScene.image(at: card.imageURL) else {
                failed = true
                return
            }
            let back = await CardScene.backImage()
            guard let model = await CardScene.makeCard(
                front: front, back: back, foil: CardFoil.matching(rarity ?? initialRarity ?? rarities.first))
            else {
                failed = true
                return
            }
            entity = model
            content.add(model)

            // Interpolation vers l'orientation visée : la carte a de l'inertie
            _ = content.subscribe(to: SceneEvents.Update.self) { event in
                let factor = min(Float(event.deltaTime) * 11, 1)
                model.orientation = simd_slerp(model.orientation, spin.target, factor)
            }
        }
        .gesture(rotation)
        // Deux taps remettent la carte à plat, un seul referme : il faut les composer
        // explicitement, sinon le tap simple part dès le premier doigt posé.
        .gesture(
            TapGesture(count: 2).onEnded {
                resting = .zero
                spin.target = Self.orientation(for: .zero)
            }
            .exclusively(before: TapGesture().onEnded { dismiss() }))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.name)
        .accessibilityHint(t("ios.card.rotateHint"))
    }

    private var rotation: some Gesture {
        DragGesture()
            .onChanged { value in
                spin.target = Self.orientation(for: Self.offset(resting, value.translation))
            }
            .onEnded { value in
                resting = Self.offset(resting, value.translation)
                spin.target = Self.orientation(for: resting)
            }
    }

    private var raritySwitcher: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xs) {
                ForEach(rarities, id: \.self) { value in
                    Button(value) { rarity = value }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .tint(rarity == value ? Color.accentColor : nil)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(t("ios.card.foil"))
    }

    private static func offset(_ base: CGSize, _ translation: CGSize) -> CGSize {
        CGSize(width: base.width + translation.width, height: base.height + translation.height)
    }

    /// Glissement horizontal → rotation libre sur 360° (on voit le dos) ; vertical → bascule
    /// bornée à ±75°, pour ne pas passer par les pôles.
    private static func orientation(for offset: CGSize) -> simd_quatf {
        let yaw = Float(offset.width) * 0.009
        let pitch = min(max(Float(offset.height) * 0.009, -1.31), 1.31)
        return simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
            * simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    }
}
