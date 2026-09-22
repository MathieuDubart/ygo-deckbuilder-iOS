import SwiftUI

/// Pile ouvrable : Cimetière, cartes bannies, Extra Deck.
nonisolated enum DuelPile: String, Hashable, Sendable {
    case grave, banished, extra

    var titleKey: String { "duel.board.\(rawValue)" }
}

/// Ce que le terrain signale à l'écran (actions, choix d'une zone, piles).
struct DuelBoardHandlers {
    var onCard: (DuelCardRef) -> Void
    var onZone: (DuelZone) -> Void
    var onPile: (Int, DuelPile) -> Void
}

/// Terrain vu depuis ta place : l'adversaire en haut (miroir), toi en bas, les Zones Monstre
/// Extra au milieu. Colonnes : [Terrain/Extra] [5 zones] [Cimetière/Deck], bannies au milieu.
struct DuelBoardView: View {
    let state: DuelState
    let model: DuelModel
    /// Zones déjà choisies (invite PLACE à plusieurs zones)
    let picked: Set<String>
    let handlers: DuelBoardHandlers

    /// Pendant le replay, le terrain est figé : pas d'actions ni de zones à choisir
    private var actions: [String: [DuelAction]] { model.playing ? [:] : state.prompt?.actionsByCard ?? [:] }
    private var placeable: Set<String> { model.playing ? [] : state.prompt?.placeableZones ?? [] }
    private var chainKeys: Set<String> { Set(state.chain.map(\.card.key)) }

    var body: some View {
        VStack(spacing: Spacing.s) {
            DuelHandRow(player: state.opponent, controller: 1, state: state, model: model, actions: actions, onCard: handlers.onCard)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xxs), count: 7), spacing: Spacing.xxs) {
                ForEach(cells) { cell in
                    cellView(cell)
                }
            }
            DuelHandRow(player: state.me, controller: 0, state: state, model: model, actions: actions, onCard: handlers.onCard)
        }
    }

    // MARK: - Cases

    private struct Cell: Identifiable {
        enum Content {
            case zone(card: DuelCard?, zones: [DuelZone], tint: Color, dashed: Bool)
            case pile(controller: Int, pile: DuelPile)
            case deck(controller: Int)
            case chain
            case empty
        }
        let id: String
        let content: Content
    }

    private var cells: [Cell] {
        let me = state.me
        let opp = state.opponent
        let mirror = [4, 3, 2, 1, 0]
        func zone(_ id: String, _ card: DuelCard?, _ zones: [DuelZone], _ tint: Color, dashed: Bool = false) -> Cell {
            Cell(id: id, content: .zone(card: card, zones: zones, tint: tint, dashed: dashed))
        }
        func z(_ controller: Int, _ location: String, _ sequence: Int) -> DuelZone {
            DuelZone(controller: controller, location: location, sequence: sequence)
        }
        func at(_ list: [DuelCard?], _ i: Int) -> DuelCard? { i < list.count ? list[i] : nil }

        var out: [Cell] = []
        // Adversaire : Magies & Pièges
        out.append(Cell(id: "od", content: .deck(controller: 1)))
        out += mirror.map { zone("os\($0)", at(opp.spells, $0), [z(1, "SZONE", $0)], Theme.spell) }
        out.append(Cell(id: "oe", content: .pile(controller: 1, pile: .extra)))
        // Adversaire : Monstres
        out.append(Cell(id: "og", content: .pile(controller: 1, pile: .grave)))
        out += mirror.map { zone("om\($0)", at(opp.monsters, $0), [z(1, "MZONE", $0)], Theme.monster) }
        out.append(zone("of", at(opp.spells, 5), [z(1, "SZONE", 5)], Theme.spell, dashed: true))
        // Milieu : bannies adverses, Zones Monstre Extra partagées, chaîne, tes bannies
        out.append(Cell(id: "ob", content: .pile(controller: 1, pile: .banished)))
        out.append(Cell(id: "x1", content: .empty))
        out.append(zone("el", at(me.monsters, 5) ?? at(opp.monsters, 6), [z(0, "MZONE", 5), z(1, "MZONE", 6)], Theme.extra))
        out.append(Cell(id: "ch", content: .chain))
        out.append(zone("er", at(me.monsters, 6) ?? at(opp.monsters, 5), [z(0, "MZONE", 6), z(1, "MZONE", 5)], Theme.extra))
        out.append(Cell(id: "x2", content: .empty))
        out.append(Cell(id: "mb", content: .pile(controller: 0, pile: .banished)))
        // Toi : Monstres
        out.append(zone("mf", at(me.spells, 5), [z(0, "SZONE", 5)], Theme.spell, dashed: true))
        out += (0..<5).map { zone("mm\($0)", at(me.monsters, $0), [z(0, "MZONE", $0)], Theme.monster) }
        out.append(Cell(id: "mg", content: .pile(controller: 0, pile: .grave)))
        // Toi : Magies & Pièges
        out.append(Cell(id: "me", content: .pile(controller: 0, pile: .extra)))
        out += (0..<5).map { zone("ms\($0)", at(me.spells, $0), [z(0, "SZONE", $0)], Theme.spell) }
        out.append(Cell(id: "md", content: .deck(controller: 0)))
        return out
    }

    @ViewBuilder
    private func cellView(_ cell: Cell) -> some View {
        switch cell.content {
        case .zone(let card, let zones, let tint, let dashed):
            DuelZoneCell(
                card: card, zones: zones, tint: tint, dashed: dashed, model: model,
                placeable: zones.first { placeable.contains($0.key) },
                picked: zones.contains { picked.contains($0.key) },
                actionable: card.map { actions[$0.ref.key] != nil } ?? false,
                inChain: card.map { chainKeys.contains($0.ref.key) } ?? false,
                onCard: handlers.onCard, onZone: handlers.onZone)
        case .pile(let controller, let pile):
            DuelPileCell(
                player: state.players[controller], controller: controller, pile: pile, model: model,
                actionable: pileList(controller, pile).contains { actions[$0.ref.key] != nil }
            ) { handlers.onPile(controller, pile) }
        case .deck(let controller):
            DuelDeckCell(count: state.players[controller].deckCount)
        case .chain:
            DuelChainCell(chain: state.chain, model: model)
        case .empty:
            Color.clear.aspectRatio(Theme.cardAspect, contentMode: .fit)
        }
    }

    private func pileList(_ controller: Int, _ pile: DuelPile) -> [DuelCard] {
        let p = state.players[controller]
        switch pile {
        case .grave: return p.grave
        case .banished: return p.banished
        case .extra: return p.extra
        }
    }
}

// MARK: - Cartes

/// Dos de carte (générique, aux couleurs de l'app).
struct DuelCardBack: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [Color(red: 0.45, green: 0.27, blue: 0.16), Color(red: 0.24, green: 0.14, blue: 0.09)],
                    center: .center, startRadius: 2, endRadius: 60)
            )
            .overlay {
                Ellipse()
                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                    .padding(6)
            }
            .aspectRatio(Theme.cardAspect, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// Face d'une carte du duel : visuel si on la connaît, dos sinon (tes cartes posées sont
/// visibles pour toi, avec un voile).
struct DuelCardFace: View {
    let code: Int
    var position: DuelPosition?
    let model: DuelModel
    var width: ImagePipeline.Width = .thumb

    var body: some View {
        if let summary = model.card(code) {
            CardArt(card: summary, width: width)
                .overlay(alignment: .topTrailing) {
                    if position?.isFaceDown == true {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(.black.opacity(0.45))
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(3)
                        }
                    }
                }
        } else {
            DuelCardBack()
        }
    }
}

/// Carte posée sur le Terrain : rotation en Défense, ATK/DEF, Matériels.
struct DuelFieldCard: View {
    let card: DuelCard
    let model: DuelModel

    var body: some View {
        let defense = card.position?.isDefense == true
        DuelCardFace(code: card.code, position: card.position, model: model)
            .rotationEffect(.degrees(defense ? 90 : 0))
            .scaleEffect(defense ? Theme.cardAspect : 1)
            .overlay(alignment: .topLeading) {
                if !card.overlays.isEmpty {
                    badge("\(card.overlays.count)", tint: Theme.extra)
                }
            }
            .overlay(alignment: .bottom) {
                if card.location == .mzone, card.position?.isFaceDown == false, let atk = card.attack {
                    Text(card.link != nil ? "\(atk) L\(card.link ?? 0)" : "\(atk)/\(card.defense ?? 0)")
                        .font(.system(size: 8, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .background(.black.opacity(0.75), in: .rect(cornerRadius: 3))
                        .offset(y: 4)
                }
            }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold).monospacedDigit())
            .foregroundStyle(.black)
            .padding(.horizontal, 3)
            .background(tint, in: .rect(cornerRadius: 3))
            .padding(2)
    }
}

private struct DuelZoneCell: View {
    let card: DuelCard?
    let zones: [DuelZone]
    let tint: Color
    let dashed: Bool
    let model: DuelModel
    let placeable: DuelZone?
    let picked: Bool
    let actionable: Bool
    let inChain: Bool
    let onCard: (DuelCardRef) -> Void
    let onZone: (DuelZone) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        ZStack {
            shape.fill(placeable != nil ? Color.accentColor.opacity(picked ? 0.4 : 0.18) : Color.primary.opacity(0.04))
            shape.strokeBorder(
                borderColor,
                style: StrokeStyle(lineWidth: placeable != nil || actionable || inChain ? 2 : 0.5, dash: dashed ? [3] : []))
            if let card {
                // Carte qui arrive : elle jaillit (Invocation, pose…)
                DuelFieldCard(card: card, model: model)
                    .padding(1)
                    .id(card.code)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.3).combined(with: .opacity),
                        removal: .scale(scale: 1.3).combined(with: .opacity)))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.45), value: card?.code)
        .aspectRatio(Theme.cardAspect, contentMode: .fit)
        .modifier(PulseGlow(active: actionable))
        .contentShape(.rect)
        .onTapGesture {
            if let placeable {
                onZone(placeable)
            } else if let card {
                onCard(card.ref)
            }
        }
        .accessibilityAddTraits(placeable != nil || card != nil ? .isButton : [])
        .accessibilityLabel(card.map { model.name($0.code) } ?? "")
    }

    private var borderColor: Color {
        if placeable != nil || actionable { return .accentColor }
        if inChain { return Theme.trap }
        return tint.opacity(0.35)
    }
}

private struct DuelPileCell: View {
    let player: DuelPlayer
    let controller: Int
    let pile: DuelPile
    let model: DuelModel
    let actionable: Bool
    let open: () -> Void

    private var list: [DuelCard] {
        switch pile {
        case .grave: player.grave
        case .banished: player.banished
        case .extra: player.extra
        }
    }

    private var count: Int { pile == .extra ? player.extraCount : list.count }

    var body: some View {
        Button(action: open) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(actionable ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: actionable ? 2 : 0.5)
                if count > 0 {
                    if pile == .extra {
                        DuelCardBack()
                    } else if let top = list.last {
                        DuelCardFace(code: top.code, model: model)
                            .saturation(pile == .banished ? 0.4 : 1)
                    }
                }
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .background(.black.opacity(0.75), in: .capsule)
                    .padding(2)
            }
            .aspectRatio(Theme.cardAspect, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(list.isEmpty)
        .modifier(PulseGlow(active: actionable))
        .accessibilityLabel("\(t(pile.titleKey)) \(count)")
    }
}

private struct DuelDeckCell: View {
    let count: Int

    var body: some View {
        ZStack(alignment: .bottom) {
            if count > 0 {
                DuelCardBack()
            } else {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
            }
            Text("\(count)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .background(.black.opacity(0.75), in: .capsule)
                .padding(2)
        }
        .aspectRatio(Theme.cardAspect, contentMode: .fit)
        .accessibilityLabel("\(t("duel.board.deck")) \(count)")
    }
}

private struct DuelChainCell: View {
    let chain: [DuelChainLink]
    let model: DuelModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            ForEach(Array(chain.enumerated()), id: \.offset) { i, link in
                DuelCardFace(code: link.card.code, model: model)
                    .scaleEffect(0.75)
                    .offset(x: CGFloat(i) * 4 - CGFloat(chain.count - 1) * 2, y: CGFloat(-i) * 4)
            }
            if !chain.isEmpty {
                Text("\(t("duel.board.chain")) \(chain.count)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 4)
                    .background(Theme.trap, in: .capsule)
                    .offset(y: 4)
            }
        }
        .aspectRatio(Theme.cardAspect, contentMode: .fit)
    }
}

// MARK: - Mains

private struct DuelHandRow: View {
    let player: DuelPlayer
    let controller: Int
    let state: DuelState
    let model: DuelModel
    let actions: [String: [DuelAction]]
    let onCard: (DuelCardRef) -> Void

    var body: some View {
        let mine = controller == 0
        let active = state.turnPlayer == controller && state.finished == nil
        HStack(spacing: Spacing.s) {
            if !mine { Spacer(minLength: 0) }
            if mine { plate(active: active) }
            ScrollView(.horizontal) {
                HStack(spacing: mine ? Spacing.xxs : -8) {
                    ForEach(player.hand) { card in
                        let actionable = actions[card.ref.key] != nil
                        DuelCardFace(code: card.code, model: model)
                            .frame(width: mine ? 50 : 32)
                            .overlay {
                                if actionable {
                                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                        .strokeBorder(Color.accentColor, lineWidth: 2)
                                }
                            }
                            .offset(y: actionable ? -3 : 0)
                            .modifier(PulseGlow(active: actionable))
                            .onTapGesture { onCard(card.ref) }
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(mine ? .leading : .trailing)
            if !mine { plate(active: active) }
        }
        .frame(minHeight: mine ? 76 : 50)
    }

    private func plate(active: Bool) -> some View {
        VStack(spacing: 0) {
            Text(controller == 0 ? t("duel.board.you") : t("duel.board.opponent"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            // PV qui défilent pendant le replay
            let lp = model.lpOverride.flatMap { controller < $0.count ? $0[controller] : nil } ?? player.lp
            Text(L10n.shared.number(lp))
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText(value: Double(lp)))
                .animation(.snappy(duration: 0.6), value: lp)
                .foregroundStyle(lp <= 1000 ? Theme.danger : .primary)
            Text(t("duel.board.lp"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 70)
        .padding(.vertical, Spacing.xs)
        .glassEffect(active ? .regular.tint(.accentColor.opacity(0.3)) : .regular, in: .rect(cornerRadius: Radius.s))
    }
}

/// Halo doré qui pulse autour d'une carte jouable.
struct PulseGlow: ViewModifier {
    let active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            content.phaseAnimator([false, true]) { view, bright in
                view.shadow(color: Color.accentColor.opacity(bright ? 0.9 : 0.4), radius: bright ? 9 : 3)
            } animation: { _ in .easeInOut(duration: 0.8) }
        } else {
            content
        }
    }
}
