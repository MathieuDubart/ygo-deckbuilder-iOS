import SwiftUI

/// Guide de jeu d'une liste : comment le deck gagne, ses cartes clés, des combos pas à pas,
/// quoi faire en premier / en second et les erreurs à éviter. Calculé à partir des effets
/// des cartes ; rédigé par l'IA du serveur quand elle existe (switch mémorisé).
struct DeckGuideView: View {
    let cards: [DeckCardEntry]
    var name: String?
    var onInspect: (Int) -> Void = { _ in }

    enum Mode: String { case rules = "RULES", ai = "AI" }

    @Environment(AppState.self) private var app
    @AppStorage("guide.mode") private var modeRaw = Mode.rules.rawValue
    @State private var rules: Loadable<DeckGuide> = .idle
    @State private var ai: DeckGuide?
    @State private var aiError: String?
    @State private var writing = false
    @State private var aiAttempt = 0

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .rules }
    private var aiAvailable: Bool { rules.value?.aiAvailable ?? false }
    private var wantsAI: Bool { aiAvailable && mode == .ai }

    /// Empreinte stable de la liste (ordre indifférent).
    private var fingerprint: String {
        cards.map { "\($0.zone.rawValue)\($0.cardId)x\($0.quantity)" }.sorted().joined(separator: ",")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label(t("guide.title"), systemImage: "book.pages")
                    .font(.title3.bold())
                Spacer()
                if let guide = shown {
                    Pill(
                        text: guide.source == .ai
                            ? (guide.model.map { t("guide.source.aiWithModel", ["model": $0]) } ?? t("guide.source.ai"))
                            : t("guide.source.rules"),
                        tint: guide.source == .ai ? .accentColor : .secondary)
                }
            }

            if aiAvailable {
                Picker(t("guide.mode.label"), selection: $modeRaw) {
                    Text(t("guide.mode.RULES")).tag(Mode.rules.rawValue)
                    Text(t("guide.mode.AI")).tag(Mode.ai.rawValue)
                }
                .pickerStyle(.segmented)
            }

            if wantsAI && writing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(t("guide.writing")).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if wantsAI, !writing, let aiError {
                HStack(alignment: .firstTextBaseline) {
                    Text(t("guide.aiError", ["error": aiError]))
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                    Spacer()
                    Button(t("common.actions.retry")) { aiAttempt += 1 }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }

            switch rules {
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(Theme.danger)
            default:
                if let guide = shown {
                    GuideBody(guide: guide, onInspect: onInspect)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
        .task(id: fingerprint) {
            guard !cards.isEmpty else {
                rules = .failed(t("guide.nothing"))
                return
            }
            ai = nil
            rules = await .fetch(rules) { try await app.api.guide(DeckGuideRequest(name: name, cards: cards, ai: false)) }
        }
        .task(id: "\(fingerprint)|\(wantsAI)|\(aiAttempt)") {
            guard wantsAI else { writing = false; return }
            await pollAI()
        }
    }

    private var shown: DeckGuide? {
        if wantsAI, let ai { return ai }
        return rules.value
    }

    /// La rédaction IA tourne en arrière-plan côté API : on redemande toutes les 3 s.
    private func pollAI() async {
        writing = true
        aiError = nil
        defer { writing = false }
        while !Task.isCancelled {
            do {
                let guide = try await app.api.guide(DeckGuideRequest(name: name, cards: cards, ai: true))
                switch guide.aiStatus {
                case .ready where guide.source == .ai:
                    ai = guide
                    return
                case .pending:
                    try await Task.sleep(for: .seconds(3))
                case .error:
                    aiError = guide.aiError ?? t("common.status.error")
                    return
                default:
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                aiError = error.localizedDescription
                return
            }
        }
    }
}

// MARK: - Contenu du guide

private struct GuideBody: View {
    let guide: DeckGuide
    let onInspect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(guide.summary)
                .font(.callout)
                .textSelection(.enabled)

            if !guide.styles.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(guide.styles, id: \.self) { Pill(text: $0, tint: .accentColor) }
                }
            }

            if !guide.stats.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(guide.stats, id: \.label) { stat in
                        StatTile(label: stat.label, value: stat.value, tint: tone(stat.tone))
                            .accessibilityHint(stat.hint)
                    }
                }
            }

            section(t("guide.sections.gamePlan"), systemImage: "flag.checkered", items: guide.gamePlan, numbered: true)

            if !guide.combos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(t("guide.sections.combos", ["count": guide.combos.count]), systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                    Text(t("guide.sections.combosDisclaimer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(guide.combos.enumerated()), id: \.offset) { index, combo in
                        ComboView(combo: combo, guide: guide, expandedByDefault: index == 0, onInspect: onInspect)
                    }
                }
            }

            if !guide.keyCards.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(t("guide.sections.keyCards"), systemImage: "key.fill").font(.headline)
                    ForEach(guide.keyCards, id: \.cardId) { key in
                        if let card = guide.card(key.cardId) {
                            Button { onInspect(key.cardId) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    CardArt(card: card, width: .thumb).frame(width: 44)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(card.name).font(.subheadline.weight(.semibold))
                                        FlowLayout(spacing: 4) {
                                            ForEach(key.roles.filter { $0 != .unknown }, id: \.self) { role in
                                                Pill(text: t("guide.roles.\(role.rawValue)"), tint: .accentColor)
                                            }
                                        }
                                        Text(key.why).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !guide.goingFirst.isEmpty || !guide.goingSecond.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(t("guide.sections.firstSecond"), systemImage: "arrow.left.arrow.right").font(.headline)
                    subsection(t("guide.sections.goingFirst"), guide.goingFirst)
                    subsection(t("guide.sections.goingSecond"), guide.goingSecond)
                }
            }

            section(t("guide.sections.mistakes"), systemImage: "exclamationmark.triangle", items: guide.mistakes, tint: Theme.warning)
            if !guide.tips.isEmpty {
                section(t("guide.sections.tips"), systemImage: "lightbulb", items: guide.tips)
            }
        }
    }

    private func tone(_ tone: DeckGuide.Stat.Tone) -> Color {
        switch tone {
        case .good: Theme.success
        case .warn: Theme.warning
        case .bad: Theme.danger
        case .neutral: .primary
        }
    }

    @ViewBuilder
    private func section(_ title: String, systemImage: String, items: [String], numbered: Bool = false, tint: Color = .accentColor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.headline)
            if items.isEmpty {
                Text(t("guide.nothing")).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(numbered ? "\(index + 1)." : "•")
                        .font(.callout.monospacedDigit().bold())
                        .foregroundStyle(tint)
                    Text(item).font(.callout)
                }
            }
        }
    }

    @ViewBuilder
    private func subsection(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Color.accentColor)
                        Text(item).font(.callout)
                    }
                }
            }
        }
    }
}

private struct ComboView: View {
    let combo: DeckGuide.Combo
    let guide: DeckGuide
    let onInspect: (Int) -> Void
    @State private var expanded: Bool

    init(combo: DeckGuide.Combo, guide: DeckGuide, expandedByDefault: Bool, onInspect: @escaping (Int) -> Void) {
        self.combo = combo
        self.guide = guide
        self.onInspect = onInspect
        _expanded = State(initialValue: expandedByDefault)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                cardStrip(t("guide.combo.hand"), ids: combo.handIds)
                ForEach(Array(combo.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.bold().monospacedDigit())
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor.opacity(0.2), in: .circle)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.text).font(.callout)
                            if !step.cardIds.isEmpty { thumbs(step.cardIds, size: 34) }
                        }
                    }
                }
                cardStrip(t("guide.combo.endBoard"), ids: combo.endBoardIds)
            }
            .padding(.top, 8)
        } label: {
            Text(combo.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(.fill.quaternary, in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private func cardStrip(_ title: String, ids: [Int]) -> some View {
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                thumbs(ids, size: 44)
            }
        }
    }

    private func thumbs(_ ids: [Int], size: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(ids.enumerated()), id: \.offset) { _, id in
                    if let card = guide.card(id) {
                        Button { onInspect(id) } label: { CardArt(card: card, width: .thumb).frame(width: size) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
