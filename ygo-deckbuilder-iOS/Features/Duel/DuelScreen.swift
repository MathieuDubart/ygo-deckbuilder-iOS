import SwiftUI

/// Onglet Duel : simulateur (moteur EDOPro sur le serveur) contre un adversaire passif,
/// contrôlé par toi ou par le bot, et rappel des règles.
struct DuelScreen: View {
    @Environment(AppState.self) private var app
    @State private var model: DuelModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    DuelContent(model: model)
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            if model == nil { model = DuelModel(api: app.api) }
        }
    }
}

private struct DuelContent: View {
    @Bindable var model: DuelModel
    @Environment(AppState.self) private var app
    @State private var showRules = false

    var body: some View {
        content
            .navigationTitle(t("duel.page.title"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
            .onChange(of: app.pendingDuelDeckId, initial: true) {
                // « Tester en duel » depuis le deck builder : ce deck, main de départ libre
                guard let deckId = app.pendingDuelDeckId else { return }
                app.pendingDuelDeckId = nil
                model.setup.deckId = deckId
                model.setup.openingHand = []
            }
            .task(id: model.engine.value?.ready) {
                // Scripts en cours de téléchargement côté serveur : on revérifie
                while model.engine.value?.ready == false {
                    try? await Task.sleep(for: .seconds(5))
                    if Task.isCancelled { return }
                    await model.load()
                }
            }
            .sheet(isPresented: $showRules) {
                NavigationStack { RulesView() }
                    .presentationDragIndicator(.visible)
            }
            .alert(t("common.status.error"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button(t("common.actions.close"), role: .cancel) {}
            } message: {
                Text(model.error ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.resuming {
            ProgressView()
        } else if let state = model.state {
            DuelTableView(state: state, model: model, showRules: { showRules = true })
        } else {
            switch model.engine {
            case .loaded(let engine) where engine.ready:
                DuelSetupView(model: model, engine: engine) { showRules = true }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { SettingsButton() }
                    }
            case .loaded(let engine):
                ContentUnavailableView {
                    Label(engine.downloading ? t("duel.engine.loading") : t("duel.engine.unavailable"),
                          systemImage: "bolt.horizontal.circle")
                } description: {
                    Text(engine.downloading ? t("duel.engine.downloading") : (engine.error ?? ""))
                }
            default:
                LoadableView(state: model.engine, retry: model.load) { _ in EmptyView() }
            }
        }
    }
}

// MARK: - Table de jeu

private struct DuelTableView: View {
    let state: DuelState
    let model: DuelModel
    let showRules: () -> Void

    @State private var menuCard: DuelCardRef?
    @State private var pile: PileRef?
    @State private var inspected: CardLink?
    @State private var picks: [DuelZone] = []
    @State private var showLog = false
    @State private var resultDismissed = false
    /// Incrémenté à chaque gros coup : relance la secousse du terrain
    @State private var shakes = 0

    private struct PileRef: Identifiable {
        let controller: Int
        let pile: DuelPile
        var id: String { "\(controller)-\(pile.rawValue)" }
    }

    private var actions: [String: [DuelAction]] { state.prompt?.actionsByCard ?? [:] }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                turnStrip
                DuelBoardView(
                    state: state, model: model, picked: Set(picks.map(\.key)),
                    handlers: DuelBoardHandlers(
                        onCard: { tap($0) }, onZone: { pickZone($0) },
                        onPile: { pile = PileRef(controller: $0, pile: $1) }))
                    .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakes) { board, offset in
                        board.offset(x: offset, y: offset * 0.4)
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(-9, duration: 0.05)
                            SpringKeyframe(8, duration: 0.06)
                            SpringKeyframe(-6, duration: 0.06)
                            SpringKeyframe(4, duration: 0.07)
                            SpringKeyframe(-2, duration: 0.08)
                            SpringKeyframe(0, duration: 0.12)
                        }
                    }
            }
            .padding(.horizontal, Spacing.s)
            .padding(.bottom, Spacing.l)
        }
        .overlay { DuelFxStage(model: model) }
        .overlay {
            if let result = state.finished, !resultDismissed, !model.playing {
                ZStack {
                    if result.winner == 0 { DuelConfetti() }
                    resultCard(result)
                }
            }
        }
        .onChange(of: model.fx?.id) {
            if model.fx?.shake == true, !UIAccessibility.isReduceMotionEnabled { shakes += 1 }
        }
        .onChange(of: state.finished) {
            guard let result = state.finished else { return }
            DuelSound.shared.play(result.winner == 0 ? .win : .lose)
            DuelHaptics.result(won: result.winner == 0)
        }
        .safeAreaInset(edge: .bottom) {
            if let prompt = state.prompt, state.finished == nil, !model.playing {
                // Le panneau garde sa hauteur naturelle, et défile au-delà
                ScrollView {
                    DuelPromptPanel(
                        state: state, prompt: prompt, model: model, pickedCount: picks.count,
                        resetPicks: { picks = [] }, inspect: { inspect($0) })
                        .padding(Spacing.l)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 340)
                .fixedSize(horizontal: false, vertical: true)
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.l))
                .padding(.horizontal, Spacing.s)
                .padding(.bottom, Spacing.xs)
            }
        }
        .toolbar { tableToolbar }
        .onChange(of: state.prompt?.id) {
            picks = []
            menuCard = nil
        }
        .onChange(of: state.finished) { resultDismissed = false }
        .animation(.spring(duration: 0.35), value: model.playing)
        .confirmationDialog(
            menuCard.map { model.name($0.code) } ?? "", isPresented: Binding(get: { menuCard != nil }, set: { if !$0 { menuCard = nil } }),
            titleVisibility: .visible, presenting: menuCard
        ) { card in
            ForEach(actions[card.key] ?? [], id: \.self) { action in
                Button(actionLabel(action)) { play(action) }
            }
            if card.code != 0 {
                Button(t("duel.actions.inspect")) { inspect(card.code) }
            }
        } message: { card in
            let descriptions = (actions[card.key] ?? []).compactMap(\.description)
            if !descriptions.isEmpty { Text(descriptions.joined(separator: "\n")) }
        }
        .sheet(item: $pile) { ref in
            DuelPileSheet(
                title: "\(ref.controller == 0 ? t("duel.board.you") : t("duel.board.opponent")) · \(t(ref.pile.titleKey))",
                cards: list(ref), model: model, actions: actions,
                play: { action in
                    pile = nil
                    play(action)
                })
        }
        .sheet(isPresented: $showLog) {
            DuelLogView(model: model)
        }
        .cardDetailSheet($inspected)
        .sensoryFeedback(.impact(weight: .light), trigger: state.prompt?.id)
    }

    // MARK: - En-tête

    private var turnStrip: some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(t("duel.board.turn", ["turn": state.turn]))
                    .font(.subheadline.weight(.semibold))
                Text(state.turnPlayer == 0 ? t("duel.board.yourTurn") : t("duel.board.opponentTurn"))
                    .font(.caption)
                    .foregroundStyle(state.turnPlayer == 0 ? Color.accentColor : Theme.trap)
            }
            Spacer(minLength: Spacing.s)
            HStack(spacing: 2) {
                ForEach(DuelPhase.allCases, id: \.self) { phase in
                    Text(t("duel.phaseShort.\(phase.rawValue)"))
                        .font(.system(size: 10, weight: .bold).monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .foregroundStyle(phase == state.phase ? Color.black : .secondary)
                        .background(phase == state.phase ? Color.accentColor : .clear, in: .rect(cornerRadius: 5))
                        .accessibilityLabel(t("duel.phases.\(phase.rawValue)"))
                }
            }
            if model.busy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, Spacing.xs)
    }

    @ToolbarContentBuilder
    private var tableToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(t("duel.log.title"), systemImage: "list.bullet.rectangle") { showLog = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu(t("ios.common.more"), systemImage: "ellipsis") {
                Toggle(t("duel.controls.sound"), systemImage: "speaker.wave.2", isOn: Binding(
                    get: { DuelFxSettings.shared.sound },
                    set: { DuelFxSettings.shared.sound = $0 }))
                Picker(t("duel.controls.speed.label"), selection: Binding(
                    get: { DuelFxSettings.shared.speed },
                    set: { DuelFxSettings.shared.speed = $0 })
                ) {
                    ForEach(DuelFxSpeed.allCases) { speed in
                        Text(t("duel.controls.speed.\(speed.rawValue)")).tag(speed)
                    }
                }
                .pickerStyle(.menu)
                Picker(t("duel.controls.chains.label"), selection: Binding(
                    get: { state.chainPrompts },
                    set: { mode in Task { await model.setChainPrompts(mode) } })
                ) {
                    ForEach(DuelChainPrompts.allCases) { mode in
                        Text(t("duel.controls.chains.\(mode.rawValue)")).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.busy)
                Button(t("duel.controls.restart"), systemImage: "arrow.counterclockwise") {
                    Task { await model.start() }
                }
                .disabled(model.busy)
                Button(t("duel.page.rules"), systemImage: "book.closed", action: showRules)
                Divider()
                Button(t("duel.controls.leave"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await model.leave() }
                }
                .disabled(model.busy)
            }
        }
    }

    // MARK: - Interactions

    private func tap(_ card: DuelCardRef) {
        guard !model.busy else { return }
        if actions[card.key] != nil {
            menuCard = card
        } else if card.code != 0 {
            inspect(card.code)
        }
    }

    private func pickZone(_ zone: DuelZone) {
        guard case .place(_, let count, _)? = state.prompt?.kind, !model.busy else { return }
        var next = picks.filter { $0.key != zone.key }
        next.append(zone)
        if next.count >= count {
            let zones = Array(next.prefix(count))
            Task { await model.respond(DuelAnswer(zones: zones)) }
        } else {
            picks = next
        }
    }

    private func play(_ action: DuelAction) {
        menuCard = nil
        Task { await model.respond(DuelAnswer(action: .init(kind: action.kind, index: action.index))) }
    }

    private func inspect(_ code: Int) {
        guard let summary = model.card(code) else { return }
        inspected = CardLink(cardId: summary.id)
    }

    private func actionLabel(_ action: DuelAction) -> String {
        if action.kind == "ATTACK", action.direct == true { return t("duel.actions.ATTACK_DIRECT") }
        return t("duel.actions.\(action.kind)")
    }

    private func list(_ ref: PileRef) -> [DuelCard] {
        let p = state.players[ref.controller]
        switch ref.pile {
        case .grave: return p.grave
        case .banished: return p.banished
        case .extra: return p.extra
        }
    }

    // MARK: - Fin du duel

    private func resultCard(_ result: DuelResult) -> some View {
        let title = result.winner == nil ? t("duel.result.draw") : result.winner == 0 ? t("duel.result.win") : t("duel.result.lose")
        return VStack(spacing: Spacing.m) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundStyle(result.winner == 0 ? Color.accentColor : .secondary)
            Text(title).font(.title.bold())
            if let reason = result.reason {
                Text(reason).font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(spacing: Spacing.s) {
                Button {
                    Task { await model.start() }
                } label: {
                    Text(t("duel.result.rematch")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button {
                    Task { await model.leave() }
                } label: {
                    Text(t("duel.result.newSetup")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                Button(t("duel.result.review")) { resultDismissed = true }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.l))
        .padding(Spacing.l)
        .sensoryFeedback(.success, trigger: result.winner == 0)
    }
}

// MARK: - Piles

private struct DuelPileSheet: View {
    let title: String
    let cards: [DuelCard]
    let model: DuelModel
    let actions: [String: [DuelAction]]
    let play: (DuelAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var inspected: CardLink?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: Spacing.m)], spacing: Spacing.m) {
                    // Le dessus de la pile en premier
                    ForEach(cards.reversed()) { card in
                        VStack(spacing: Spacing.xs) {
                            DuelCardFace(code: card.code, model: model, width: .tile)
                                .onTapGesture {
                                    if let summary = model.card(card.code) { inspected = CardLink(cardId: summary.id) }
                                }
                            ForEach(actions[card.ref.key] ?? [], id: \.self) { action in
                                Button(t("duel.actions.\(action.kind)")) { play(action) }
                                    .buttonStyle(.glassProminent)
                                    .controlSize(.small)
                                    .font(.caption)
                            }
                        }
                    }
                }
                .padding(Spacing.l)
            }
            .overlay {
                if cards.isEmpty {
                    ContentUnavailableView(t("duel.board.emptyPile"), systemImage: "tray")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
                }
            }
        }
        .cardDetailSheet($inspected)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Journal

private struct DuelLogView: View {
    let model: DuelModel
    @Environment(\.dismiss) private var dismiss
    @State private var inspected: CardLink?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(model.log) { event in
                    line(event)
                        .id(event.id)
                        .listRowSeparator(isTurn(event) ? .visible : .hidden)
                }
                .listStyle(.plain)
                .overlay {
                    if model.log.isEmpty {
                        ContentUnavailableView(t("duel.log.empty"), systemImage: "text.alignleft")
                    }
                }
                .onAppear {
                    if let last = model.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .cardDetailSheet($inspected)
            .navigationTitle(t("duel.log.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func isTurn(_ event: DuelEvent) -> Bool {
        if case .turn = event.kind { return true }
        return false
    }

    private func who(_ player: Int) -> String { player == 0 ? "you" : "opponent" }

    @ViewBuilder
    private func line(_ event: DuelEvent) -> some View {
        switch event.kind {
        case .turn(let player):
            Text(t("duel.log.TURN", ["turn": event.turn, "player": who(player)]))
                .font(.subheadline.weight(.semibold))
                .padding(.top, Spacing.s)
        case .phase(let phase):
            Text(t("duel.phases.\(phase.rawValue)"))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
        case .draw(let player, let count, let codes):
            logText(codes.isEmpty
                ? L10n.shared.rich("duel.log.DRAW_hidden", ["player": who(player), "count": count])
                : L10n.shared.rich("duel.log.DRAW", ["player": who(player), "cards": codes.map(model.name).joined(separator: ", ")]))
        case .summon(let player, let code, let how):
            cardLine("duel.log.SUMMON_\(how)", ["player": who(player), "card": model.name(code)], code: code)
        case .set(let player):
            logText(L10n.shared.rich("duel.log.SET", ["player": who(player)]))
        case .activate(let player, let code, let link, let description):
            VStack(alignment: .leading, spacing: 2) {
                cardLine("duel.log.ACTIVATE", ["link": link, "player": who(player), "card": model.name(code)], code: code)
                if let description {
                    Text(description).font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .chainNegated(let link):
            logText(L10n.shared.rich("duel.log.CHAIN_NEGATED", ["link": link]))
        case .move(let code, let from, let to):
            cardLine("duel.log.MOVE", [
                "card": model.name(code), "from": t("duel.locations.\(from.rawValue)"), "to": t("duel.locations.\(to.rawValue)"),
            ], code: code)
        case .attack(_, let code, let target):
            if let target {
                cardLine("duel.log.ATTACK", ["card": model.name(code), "target": model.name(target)], code: code)
            } else {
                cardLine("duel.log.ATTACK_direct", ["card": model.name(code)], code: code)
            }
        case .damage(let player, let amount, let cost):
            logText(L10n.shared.rich(cost ? "duel.log.DAMAGE_cost" : "duel.log.DAMAGE", ["player": who(player), "amount": amount]))
                .foregroundStyle(Theme.danger)
        case .recover(let player, let amount):
            logText(L10n.shared.rich("duel.log.RECOVER", ["player": who(player), "amount": amount]))
                .foregroundStyle(Theme.success)
        case .coin(let results):
            logText(L10n.shared.rich("duel.log.COIN", ["results": results.map { t($0 ? "duel.log.heads" : "duel.log.tails") }.joined(separator: ", ")]))
        case .dice(let results):
            logText(L10n.shared.rich("duel.log.DICE", ["results": results.map(String.init).joined(separator: ", ")]))
        case .win(let winner):
            logText(winner == nil ? L10n.shared.rich("duel.log.WIN_draw") : L10n.shared.rich("duel.log.WIN", ["player": who(winner ?? 0)]))
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
        case .unknown:
            EmptyView()
        }
    }

    private func logText(_ text: AttributedString) -> some View {
        Text(text).font(.footnote)
    }

    /// Ligne qui cite une carte : un toucher ouvre sa fiche.
    private func cardLine(_ key: String, _ args: [String: any Sendable], code: Int) -> some View {
        logText(L10n.shared.rich(key, args))
            .contentShape(.rect)
            .onTapGesture {
                if let summary = model.card(code) { inspected = CardLink(cardId: summary.id) }
            }
    }
}
