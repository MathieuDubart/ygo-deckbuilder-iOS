import SwiftUI

/// Préparation du duel : ton deck, qui commence, ta main de départ, l'adversaire et son plateau.
struct DuelSetupView: View {
    @Bindable var model: DuelModel
    let engine: DuelEngineStatus
    let showRules: () -> Void

    @Environment(AppState.self) private var app
    @State private var decks: Loadable<[DeckListItem]> = .idle
    @State private var addingCard = false

    private static let handMax = 6
    private static let sourceURL = URL(string: "https://github.com/MathieuDubart/ygo-deckbuilder")!

    var body: some View {
        Form {
            LoadableView(state: decks, retry: loadDecks) { decks in
                if decks.isEmpty {
                    ContentUnavailableView(t("duel.setup.noDecks"), systemImage: "rectangle.stack.badge.plus")
                } else {
                    deckSection(decks)
                    opponentSection(decks)
                    boardSection
                    startSection
                }
            }
        }
        .task(id: app.decksVersion) { await loadDecks() }
        .sheet(isPresented: $addingCard) {
            DuelCardSearchSheet { card in
                addToBoard(card)
            }
        }
    }

    private func loadDecks() async {
        decks = await .fetch(decks) { try await app.api.decks() }
        // Deck jouable choisi d'office ; un deck supprimé depuis la dernière config est oublié
        guard let list = decks.value, !list.isEmpty, !list.contains(where: { $0.id == model.setup.deckId }) else { return }
        let best = list.first { $0.mainCount >= 40 } ?? list.max { $0.mainCount < $1.mainCount }
        model.setup.deckId = best?.id ?? ""
        model.setup.openingHand = []
    }

    // MARK: - Sections

    private func deckSection(_ decks: [DeckListItem]) -> some View {
        Section {
            Picker(t("duel.setup.deck"), selection: $model.setup.deckId) {
                ForEach(decks) { deck in
                    Text("\(deck.name) (\(deck.mainCount))").tag(deck.id)
                }
            }
            .onChange(of: model.setup.deckId) { model.setup.openingHand = [] }

            Picker(t("duel.setup.first.label"), selection: $model.setup.goingFirst) {
                Text(t("duel.setup.first.me")).tag(true)
                Text(t("duel.setup.first.opponent")).tag(false)
            }
            .pickerStyle(.segmented)

            Stepper(value: $model.setup.startingLP, in: 500...99_500, step: 500) {
                LabeledContent(t("duel.setup.lp"), value: L10n.shared.number(model.setup.startingLP))
            }

            if !model.setup.deckId.isEmpty {
                NavigationLink {
                    DuelOpeningHandView(deckId: model.setup.deckId, hand: $model.setup.openingHand, max: Self.handMax)
                } label: {
                    LabeledContent(t("duel.setup.hand.label"),
                                   value: t("duel.setup.hand.count", ["count": model.setup.openingHand.count, "max": Self.handMax]))
                }
            }
        } header: {
            Text(t("duel.setup.title"))
        } footer: {
            Text(t("duel.setup.hand.hint"))
        }
    }

    private func opponentSection(_ decks: [DeckListItem]) -> some View {
        Section(t("duel.setup.opponent.label")) {
            ForEach(DuelOpponentControl.allCases) { control in
                Button {
                    model.setup.opponent.control = control
                } label: {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        Image(systemName: model.setup.opponent.control == control ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.setup.opponent.control == control ? Color.accentColor : .secondary)
                            .imageScale(.large)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("duel.setup.opponent.\(control.rawValue)"))
                                .foregroundStyle(.primary)
                            Text(t("duel.setup.opponent.\(control.rawValue)_hint"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Picker(t("duel.setup.opponentDeck.label"), selection: $model.setup.opponent.deckId) {
                Text(t("duel.setup.opponentDeck.copy")).tag(String?.none)
                ForEach(decks) { deck in
                    Text(deck.name).tag(String?.some(deck.id))
                }
            }
        }
    }

    private var boardSection: some View {
        Section {
            if model.setup.opponent.board.isEmpty {
                Text(t("duel.setup.board.empty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach($model.setup.opponent.board) { $entry in
                DuelBoardRow(entry: $entry, canMove: { canMove(entry, to: $0) })
            }
            .onDelete { model.setup.opponent.board.remove(atOffsets: $0) }
            Button(t("duel.setup.board.search"), systemImage: "plus") { addingCard = true }
        } header: {
            Text(t("duel.setup.board.label"))
        } footer: {
            Text(t("duel.setup.board.hint"))
        }
    }

    private var startSection: some View {
        Section {
            Button {
                Task { await model.start() }
            } label: {
                HStack {
                    if model.busy { ProgressView() }
                    Label(t("duel.setup.start"), systemImage: "bolt.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(model.setup.deckId.isEmpty || model.busy)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Button(t("duel.page.rules"), systemImage: "book.closed", action: showRules)
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(t("duel.engine.stats", ["cards": engine.cards, "scripts": engine.scripts]) + " · EDOPro / Project Ignis")
                Link(t("duel.page.source"), destination: Self.sourceURL)
            }
            .padding(.top, Spacing.s)
        }
    }

    // MARK: - Plateau adverse

    private static let limits: [DuelSetupLocation: Int] = [.mzone: 5, .szone: 5, .fzone: 1]

    private func count(_ location: DuelSetupLocation) -> Int {
        model.setup.opponent.board.filter { $0.location == location }.count
    }

    private func canMove(_ entry: DuelBoardCard, to location: DuelSetupLocation) -> Bool {
        guard entry.location != location, let limit = Self.limits[location] else { return true }
        return count(location) < limit
    }

    private func addToBoard(_ card: CardSummary) {
        let preferred: DuelSetupLocation =
            card.category == .monster ? .mzone : card.race == "Field" ? .fzone : .szone
        let room = Self.limits[preferred].map { count(preferred) < $0 } ?? true
        let location = room ? preferred : .hand
        model.setup.opponent.board.append(
            DuelBoardCard(cardId: card.id, location: location, position: location == .szone ? .set : .attack))
    }
}

/// Une carte du plateau adverse : zone, position, emplacement.
private struct DuelBoardRow: View {
    @Binding var entry: DuelBoardCard
    let canMove: (DuelSetupLocation) -> Bool
    @Environment(AppState.self) private var app
    @State private var card: CardSummary?

    var body: some View {
        HStack(spacing: Spacing.m) {
            Group {
                if let card { CardArt(card: card, width: .thumb) } else { DuelCardBack() }
            }
            .frame(width: 36)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(card?.name ?? "#\(entry.cardId)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: Spacing.xs) {
                    Menu(t("duel.setup.board.locations.\(entry.location.rawValue)")) {
                        ForEach(DuelSetupLocation.allCases) { location in
                            Button(t("duel.setup.board.locations.\(location.rawValue)")) {
                                entry.location = location
                                entry.zone = nil
                                entry.position = location == .szone ? .set : .attack
                            }
                            .disabled(!canMove(location))
                        }
                    }
                    if entry.location.onField {
                        Menu(positionLabel(entry.position)) {
                            ForEach(positions) { position in
                                Button(positionLabel(position)) { entry.position = position }
                            }
                        }
                        Menu(entry.zone.map { "\(t("duel.setup.board.zone")) \($0 + 1)" } ?? t("duel.setup.board.auto")) {
                            Button(t("duel.setup.board.auto")) { entry.zone = nil }
                            ForEach(0..<5, id: \.self) { zone in
                                Button("\(t("duel.setup.board.zone")) \(zone + 1)") { entry.zone = zone }
                            }
                        }
                    }
                }
                .font(.caption)
            }
        }
        .task(id: entry.cardId) {
            card = try? await app.api.card(entry.cardId).summary
        }
    }

    private var positions: [DuelSetupPosition] {
        entry.location == .mzone ? DuelSetupPosition.allCases : [.attack, .set]
    }

    private func positionLabel(_ position: DuelSetupPosition) -> String {
        entry.location == .szone && position == .attack
            ? t("duel.setup.board.positions.FACE_UP")
            : t("duel.setup.board.positions.\(position.rawValue)")
    }
}

/// Cartes du deck imposées dans la main de départ.
struct DuelOpeningHandView: View {
    let deckId: String
    @Binding var hand: [Int]
    let max: Int
    @Environment(AppState.self) private var app
    @State private var deck: Loadable<Deck> = .idle

    var body: some View {
        ScrollView {
            LoadableView(state: deck, retry: load) { deck in
                let main = deck.cards.filter { $0.zone == .main }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: GridWidth.compactCard), spacing: Spacing.s)], spacing: Spacing.s) {
                    ForEach(main, id: \.cardId) { entry in
                        let chosen = hand.filter { $0 == entry.cardId }.count
                        let full = chosen >= entry.quantity || hand.count >= max
                        CardArt(card: entry.card, width: .thumb, dimmed: full && chosen == 0)
                            .overlay {
                                if chosen > 0 {
                                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if chosen > 0 {
                                    Text("\(chosen)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.black)
                                        .frame(width: 18, height: 18)
                                        .background(Color.accentColor, in: .circle)
                                        .padding(2)
                                }
                            }
                            .onTapGesture {
                                if !full {
                                    hand.append(entry.cardId)
                                } else if chosen > 0, let i = hand.lastIndex(of: entry.cardId) {
                                    hand.remove(at: i)
                                }
                            }
                            .contextMenu {
                                if chosen > 0 {
                                    Button(t("duel.setup.board.remove"), systemImage: "minus.circle") {
                                        if let i = hand.lastIndex(of: entry.cardId) { hand.remove(at: i) }
                                    }
                                }
                            }
                    }
                }
                .padding(Spacing.l)
            }
        }
        .navigationTitle(t("duel.setup.hand.label"))
        .toolbar {
            ToolbarItem(placement: .status) {
                Text(t("duel.setup.hand.count", ["count": hand.count, "max": max]))
                    .font(.footnote.monospacedDigit())
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(t("duel.setup.hand.clear")) { hand = [] }
                    .disabled(hand.isEmpty)
            }
        }
        .task { await load() }
    }

    private func load() async {
        deck = await .fetch(deck) { try await app.api.deck(deckId) }
    }
}

/// Recherche d'une carte dans tout le catalogue (plateau adverse).
struct DuelCardSearchSheet: View {
    let onPick: (CardSummary) -> Void
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [CardSummary] = []
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List(results) { card in
                Button {
                    onPick(card)
                    dismiss()
                } label: {
                    CardRow(card: card) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if searched && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: t("duel.setup.board.search"))
            .navigationTitle(t("duel.setup.board.label"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
                }
            }
            .task(id: query) {
                let text = query.trimmingCharacters(in: .whitespaces)
                guard text.count >= 2 else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                results = (try? await app.api.searchCards(CardSearchQuery(q: text, pageSize: 24)).items) ?? []
                searched = true
            }
        }
        .presentationDragIndicator(.visible)
    }
}
