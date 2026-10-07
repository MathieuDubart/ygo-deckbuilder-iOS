import SwiftUI

/// Effet de brillance reproduit selon la rareté de l'impression.
nonisolated enum CardFoil: Int, CaseIterable, Identifiable, Sendable {
    case none = 0
    case gloss = 1
    case holo = 2
    case secret = 3
    case prismatic = 4

    var id: Int { rawValue }

    /// Libellé de rareté (« Secret Rare », « Starlight Rare »…) → effet le plus proche.
    /// Les raretés les plus spectaculaires sont testées en premier : « Prismatic Secret Rare »
    /// contient « secret », « Quarter Century Secret Rare » aussi.
    static func matching(_ rarity: String?) -> CardFoil {
        guard let rarity else { return .none }
        let text = rarity.lowercased()
        if text.contains("starlight") || text.contains("ghost") || text.contains("collector")
            || text.contains("quarter century") || text.contains("prismatic") {
            return .prismatic
        }
        if text.contains("secret") || text.contains("ultimate") {
            return .secret
        }
        if text.contains("ultra") || text.contains("super") || text.contains("gold")
            || text.contains("platinum") || text.contains("starfoil") || text.contains("mosaic")
            || text.contains("duel terminal") {
            return .holo
        }
        if text.contains("rare") {
            return .gloss
        }
        return .none
    }
}

/// Carte en grand qu'on peut incliner au doigt, avec la brillance de sa rareté.
/// L'inclinaison est bornée : on tourne la carte comme dans la main, on ne la retourne pas
/// (le dos des cartes n'est pas une image qu'on possède).
struct CardShowcaseView: View {
    let card: CardSummary
    /// Raretés disponibles pour cette carte (une par impression, doublons retirés).
    var rarities: [String] = []
    /// Rareté sélectionnée au départ (code d'impression scanné, par exemple).
    var initialRarity: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt: CGSize = .zero
    @State private var resting: CGSize = .zero
    @State private var rarity: String?
    @State private var started = false
    /// L'utilisateur a pris la main : l'animation d'ouverture ne remet plus la carte droite.
    @State private var touched = false

    private static let limit: CGFloat = 70

    private var foil: CardFoil { CardFoil.matching(rarity) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { dismiss() }

            VStack(spacing: Spacing.l) {
                Spacer(minLength: 0)
                cardBody
                Spacer(minLength: 0)
                if rarities.count > 1 {
                    raritySwitcher
                }
                Text(t("ios.card.rotateHint"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
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
        .task {
            guard !started else { return }
            started = true
            rarity = initialRarity ?? rarities.first
            // Petite bascule à l'ouverture : on voit tout de suite que la carte bouge
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 1.1, dampingFraction: 0.55)) {
                tilt = CGSize(width: 16, height: -8)
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard !touched else { return }
            withAnimation(.spring(response: 1.2, dampingFraction: 0.75)) { tilt = .zero }
        }
    }

    private var cardBody: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: foil == .none || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            CardArt(card: card, width: .large)
                .overlay {
                    if foil != .none {
                        shine(time: time)
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: 24, y: 16)
                .rotation3DEffect(.degrees(Double(tilt.width)), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                .rotation3DEffect(.degrees(Double(-tilt.height)), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
        }
        .frame(maxWidth: 420)
        .gesture(rotation)
        // Deux taps remettent la carte droite, un seul referme : il faut les composer
        // explicitement, sinon le tap simple part dès le premier doigt posé.
        .gesture(
            TapGesture(count: 2).onEnded {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { tilt = .zero }
                resting = .zero
            }
            .exclusively(before: TapGesture().onEnded { dismiss() }))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.name)
        .accessibilityHint(t("ios.card.rotateHint"))
    }

    /// Reflet dessiné par le shader Metal (`CardFoil.metal`), ajouté en lumière.
    private func shine(time: TimeInterval) -> some View {
        let kind = Float(foil.rawValue)
        let clock = Float(time.truncatingRemainder(dividingBy: 600))
        // Inclinaison déjà ramenée à -1…1 : le shader n'a pas à connaître la limite
        let lean = CGSize(width: tilt.width / Self.limit, height: tilt.height / Self.limit)
        return Rectangle()
            .visualEffect { effect, proxy in
                effect.colorEffect(
                    ShaderLibrary.cardFoil(
                        .float2(proxy.size), .float2(lean), .float(kind), .float(clock)))
            }
            // `CardArt` arrondit ses coins : le reflet doit suivre, sinon il déborde
            .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    private var rotation: some Gesture {
        DragGesture()
            .onChanged { value in
                touched = true
                tilt = CGSize(
                    width: Self.clamp(resting.width + value.translation.width * 0.35),
                    height: Self.clamp(resting.height + value.translation.height * 0.35))
            }
            .onEnded { value in
                resting = CGSize(
                    width: Self.clamp(resting.width + value.translation.width * 0.35),
                    height: Self.clamp(resting.height + value.translation.height * 0.35))
                tilt = resting
            }
    }

    private var raritySwitcher: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xs) {
                ForEach(rarities, id: \.self) { value in
                    Button(value) {
                        withAnimation(.snappy) { rarity = value }
                    }
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

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, -limit), limit)
    }
}
