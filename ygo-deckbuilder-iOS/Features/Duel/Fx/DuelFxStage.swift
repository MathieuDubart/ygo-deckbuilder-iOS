import SwiftUI

/// Scène posée sur le terrain pendant le replay : plans « cinématiques » (Invocations,
/// activations, attaques, tour) et effets discrets (dégâts qui flottent, pioche, phase).
struct DuelFxStage: View {
    let model: DuelModel

    var body: some View {
        ZStack {
            if let frame = model.fx {
                DuelFxScene(frame: frame, model: model)
                    .id(frame.id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: model.fx?.id)
        .contentShape(.rect)
        .onTapGesture { model.skip() }
        .overlay(alignment: .bottomTrailing) {
            if model.playing {
                Button(t("duel.fx.skip"), systemImage: "forward.fill") { model.skip() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.glass)
                    .padding(Spacing.s)
            }
        }
        // En dernier : hors replay, la scène laisse passer les touchers vers le terrain
        .allowsHitTesting(model.playing)
    }
}

private struct DuelFxScene: View {
    let frame: DuelFxFrame
    let model: DuelModel

    private var seconds: Double { Double(frame.duration) / 1000 }

    var body: some View {
        switch frame.content {
        case .start:
            Band(color: .accentColor, seconds: seconds) {
                FxTitle(text: t("duel.fx.duel"), size: 64, seconds: seconds)
            }
        case .event(let event):
            scene(event)
        }
    }

    @ViewBuilder
    private func scene(_ event: DuelEvent) -> some View {
        switch event.kind {
        case .turn(let player):
            TurnBanner(player: player, turn: event.turn, seconds: seconds)
        case .summon(let player, let code, let how):
            CutIn(player: player, code: code, model: model, label: t("duel.fx.summon.\(how)"),
                  title: model.name(code), text: nil, rays: how == "SPECIAL", color: tint(player), seconds: seconds)
        case .activate(let player, let code, let link, let description):
            CutIn(player: player, code: code, model: model, label: t("duel.fx.activate", ["link": link]),
                  title: model.name(code), text: description, rays: false, color: Theme.spell, seconds: seconds)
        case .chainNegated(let link):
            Band(color: Theme.danger, seconds: seconds) {
                Negated(link: link, seconds: seconds)
            }
        case .attack(let player, let code, let target):
            Band(color: Theme.danger, seconds: seconds) {
                AttackScene(code: code, target: target, player: player, model: model, seconds: seconds)
            }
        case .damage(let player, let amount, let cost):
            Floating(player: player, text: "−\(amount)", color: Theme.danger, big: !cost && amount >= 1000, vignette: !cost, seconds: seconds)
        case .recover(let player, let amount):
            Floating(player: player, text: "+\(amount)", color: Theme.success, big: false, vignette: false, seconds: seconds)
        case .phase(let phase):
            FxPill(text: t("duel.phases.\(phase.rawValue)"), seconds: seconds)
        case .draw(let player, let count, _):
            Corner(player: player) {
                FxPill(text: "+\(count) " + t("duel.board.hand"), seconds: seconds)
            }
        case .set(let player):
            Corner(player: player) { FxPill(text: t("duel.fx.set"), seconds: seconds) }
        case .move(let code, _, let to):
            Corner(player: 0) {
                FxPill(text: "\(model.name(code)) → \(t("duel.locations.\(to.rawValue)"))", seconds: seconds)
            }
        case .coin(let results):
            Band(color: .accentColor, seconds: seconds) {
                Coins(labels: results.map { $0 ? "★" : "☾" },
                      caption: results.map { t($0 ? "duel.log.heads" : "duel.log.tails") }.joined(separator: ", "),
                      seconds: seconds)
            }
        case .dice(let results):
            Band(color: .accentColor, seconds: seconds) {
                Coins(labels: results.map(String.init), caption: results.map(String.init).joined(separator: ", "), seconds: seconds)
            }
        case .win, .unknown:
            EmptyView()
        }
    }

    private func tint(_ player: Int) -> Color { player == 0 ? .accentColor : Theme.trap }
}

// MARK: - Éléments

/// Bandeau sombre en travers du terrain, qui s'ouvre puis se referme.
private struct Band<Content: View>: View {
    let color: Color
    let seconds: Double
    @ViewBuilder var content: () -> Content
    @State private var open = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.clear, color.opacity(0.25), color.opacity(0.25), .clear],
                startPoint: .top, endPoint: .bottom)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.85), .black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom))
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .scaleEffect(y: open ? 1 : 0.15)
                .opacity(open ? 1 : 0)
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(.spring(duration: 0.35, bounce: 0.3)) { open = true } }
    }
}

private struct FxTitle: View {
    let text: String
    let size: CGFloat
    let seconds: Double
    @State private var shown = false

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black).italic())
            .foregroundStyle(.white)
            .shadow(color: .accentColor, radius: shown ? 18 : 0)
            .tracking(shown ? 2 : 24)
            .blur(radius: shown ? 0 : 8)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.easeOut(duration: Swift.min(0.35, seconds * 0.3))) { shown = true } }
    }
}

private struct TurnBanner: View {
    let player: Int
    let turn: Int
    let seconds: Double
    @State private var x: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 2) {
                Text(t("duel.board.turn", ["turn": turn]))
                    .font(.caption.weight(.semibold))
                    .tracking(3)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.8))
                Text(player == 0 ? t("duel.board.yourTurn") : t("duel.board.opponentTurn"))
                    .font(.system(size: 36, weight: .black).italic())
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.vertical, Spacing.l)
            .frame(width: geo.size.width * 1.3)
            .background(
                LinearGradient(colors: [.clear, (player == 0 ? Color.accentColor : Theme.trap).opacity(0.9), .clear],
                               startPoint: .leading, endPoint: .trailing))
            .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.2, d: 1, tx: 0, ty: 0))
            .position(x: geo.size.width / 2 + x * geo.size.width * 0.8, y: geo.size.height / 2)
            .task {
                withAnimation(.spring(duration: 0.4, bounce: 0.2)) { x = 0 }
                try? await Task.sleep(for: .seconds(Swift.max(0.2, seconds - 0.35)))
                withAnimation(.easeIn(duration: 0.3)) { x = 1 }
            }
        }
    }
}

/// Plan d'une carte : visuel qui jaillit, halo, rayons (Invocation Spéciale), légende.
private struct CutIn: View {
    let player: Int
    let code: Int
    let model: DuelModel
    let label: String
    let title: String
    let text: String?
    let rays: Bool
    let color: Color
    let seconds: Double
    @State private var shown = false
    @State private var spin = 0.0

    var body: some View {
        Band(color: color, seconds: seconds) {
            HStack(spacing: Spacing.l) {
                ZStack {
                    if rays {
                        Circle()
                            .fill(AngularGradient(
                                gradient: Gradient(colors: Array(repeating: [color.opacity(0.6), .clear], count: 12).flatMap { $0 }),
                                center: .center))
                            .frame(width: 260, height: 260)
                            .mask(RadialGradient(colors: [.black, .clear], center: .center, startRadius: 20, endRadius: 130))
                            .rotationEffect(.degrees(spin))
                            .opacity(shown ? 1 : 0)
                    }
                    DuelCardFace(code: code, model: model, width: .medium)
                        .frame(width: 110)
                        .shadow(color: color, radius: 20)
                        .scaleEffect(shown ? 1 : 0.5)
                        .rotationEffect(.degrees(shown ? 0 : -6))
                        .brightness(shown ? 0 : 0.6)
                }
                VStack(alignment: player == 1 ? .trailing : .leading, spacing: Spacing.xxs) {
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(color)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let text {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: 180, alignment: player == 1 ? .trailing : .leading)
                .opacity(shown ? 1 : 0)
                .offset(x: shown ? 0 : (player == 1 ? -20 : 20))
            }
            .environment(\.layoutDirection, player == 1 ? .rightToLeft : .leftToRight)
            .padding(.horizontal, Spacing.l)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.4, bounce: 0.45)) { shown = true }
            withAnimation(.linear(duration: seconds)) { spin = 140 }
        }
    }
}

private struct AttackScene: View {
    let code: Int
    let target: Int?
    let player: Int
    let model: DuelModel
    let seconds: Double
    @State private var lunge: CGFloat = 0
    @State private var hit = false

    var body: some View {
        VStack(spacing: Spacing.m) {
            Text(target == nil ? t("duel.fx.direct") : t("duel.fx.attack"))
                .font(.caption.weight(.bold))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundStyle(Theme.danger)
            HStack(spacing: 56) {
                DuelCardFace(code: code, model: model, width: .tile)
                    .frame(width: 92)
                    .offset(x: lunge * 110)
                    .rotationEffect(.degrees(Double(lunge) * 6))
                    .zIndex(1)
                ZStack {
                    if let target {
                        DuelCardFace(code: target, model: model, width: .tile)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(Theme.danger.opacity(0.18))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                    .strokeBorder(Theme.danger.opacity(0.6), lineWidth: 2)
                            }
                            .aspectRatio(Theme.cardAspect, contentMode: .fit)
                            .overlay { Text("LP").font(.title.weight(.black)).foregroundStyle(.white) }
                    }
                    Circle()
                        .fill(RadialGradient(colors: [.white, Theme.danger.opacity(0.7), .clear], center: .center, startRadius: 2, endRadius: 60))
                        .frame(width: 120, height: 120)
                        .scaleEffect(hit ? 1.6 : 0.3)
                        .opacity(hit ? 0 : 1)
                        .opacity(lunge > 0.5 || hit ? 1 : 0)
                }
                .frame(width: 92)
                .offset(x: hit ? 10 : 0)
                .brightness(hit ? 0.5 : 0)
            }
            .environment(\.layoutDirection, player == 1 ? .rightToLeft : .leftToRight)
        }
        .task {
            let unit = seconds / 0.95
            try? await Task.sleep(for: .seconds(0.22 * unit))
            withAnimation(.easeIn(duration: 0.16 * unit)) { lunge = 1 }
            try? await Task.sleep(for: .seconds(0.16 * unit))
            withAnimation(.easeOut(duration: 0.3 * unit)) { hit = true }
            withAnimation(.spring(duration: 0.35 * unit, bounce: 0.4)) { lunge = 0.1 }
        }
    }
}

private struct Negated: View {
    let link: Int
    let seconds: Double
    @State private var slash = false

    var body: some View {
        VStack(spacing: Spacing.s) {
            ZStack {
                FxTitle(text: t("duel.fx.negated"), size: 44, seconds: seconds)
                Capsule()
                    .fill(Theme.danger)
                    .frame(height: 8)
                    .shadow(color: Theme.danger, radius: 12)
                    .scaleEffect(x: slash ? 1.1 : 0, anchor: .leading)
                    .rotationEffect(.degrees(-7))
            }
            Text(t("duel.log.CHAIN_NEGATED", ["link": link]))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
        }
        .onAppear { withAnimation(.easeOut(duration: 0.25).delay(0.1)) { slash = true } }
    }
}

private struct Coins: View {
    let labels: [String]
    let caption: String
    let seconds: Double
    @State private var flip = 0.0

    var body: some View {
        VStack(spacing: Spacing.m) {
            HStack(spacing: Spacing.l) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.title.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.accentColor.opacity(0.35), in: .circle)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 4))
                        .shadow(color: .accentColor, radius: 14)
                        .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0))
                }
            }
            Text(caption).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
        }
        .onAppear { withAnimation(.spring(duration: seconds * 0.7, bounce: 0.1)) { flip = 1440 } }
    }
}

private struct Floating: View {
    let player: Int
    let text: String
    let color: Color
    let big: Bool
    let vignette: Bool
    let seconds: Double
    @State private var up = false

    var body: some View {
        ZStack {
            if vignette {
                RadialGradient(colors: [Theme.danger.opacity(0.45), .clear],
                               center: player == 0 ? .bottom : .top, startRadius: 10, endRadius: 420)
                    .opacity(up ? 0 : 1)
                    .ignoresSafeArea()
            }
            Corner(player: player) {
                Text(text)
                    .font(.system(size: big ? 52 : 34, weight: .black).monospacedDigit())
                    .foregroundStyle(color)
                    .shadow(color: .black, radius: 6)
                    .scaleEffect(up ? 1 : 1.3)
                    .offset(y: up ? -40 : 0)
                    .opacity(up ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: seconds)) { up = true } }
    }
}

private struct FxPill: View {
    let text: String
    let seconds: Double
    @State private var shown = false

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .background(.black.opacity(0.7), in: .capsule)
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.spring(duration: 0.3, bounce: 0.4)) { shown = true } }
    }
}

/// Coin du joueur : en bas pour toi, en haut pour l'adversaire.
private struct Corner<Content: View>: View {
    let player: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack {
            if player == 0 { Spacer() }
            content()
                .padding(.vertical, 90)
            if player != 0 { Spacer() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Confettis

/// Pluie de confettis (victoire).
struct DuelConfetti: View {
    private struct Piece {
        var x, y, vx, vy, rotation, spin: Double
        let size: Double
        let color: Color
    }

    @State private var start = Date()
    @State private var done = false
    @State private var pieces: [Piece] = (0..<150).map { i in
        let colors: [Color] = [.accentColor, Theme.spell, Theme.trap, Theme.extra, Theme.monster]
        return Piece(
            x: 0.5 + Double.random(in: -0.08...0.08), y: 0.55,
            vx: Double.random(in: -0.012...0.012), vy: Double.random(in: -0.028 ... -0.012),
            rotation: Double.random(in: 0...(.pi)), spin: Double.random(in: -0.3...0.3),
            size: Double.random(in: 5...11), color: colors[i % colors.count])
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: done)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                let frames = elapsed * 60
                let width = Double(size.width)
                let height = Double(size.height)
                context.opacity = Swift.max(0, 1 - Swift.max(0, elapsed - 2) / 1.2)
                for piece in pieces {
                    // Trajectoire balistique calculée à partir du temps écoulé
                    let fall = 0.00022 * frames * frames
                    let x = (piece.x + piece.vx * frames) * width
                    let y = (piece.y + piece.vy * frames + fall) * height
                    var ctx = context
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(piece.rotation + piece.spin * frames))
                    ctx.fill(Path(CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)),
                             with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            // Plus rien à dessiner : on arrête l'horloge d'animation
            try? await Task.sleep(for: .seconds(3.3))
            done = true
        }
    }
}
