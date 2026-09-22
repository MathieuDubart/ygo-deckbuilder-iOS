import SwiftUI

/// Ce que le moteur attend : consigne, puis le choix adapté (cartes, zones, oui/non…).
/// Les actions de Main / Battle Phase se jouent directement sur le terrain.
struct DuelPromptPanel: View {
    let state: DuelState
    let prompt: DuelPrompt
    let model: DuelModel
    let pickedCount: Int
    let resetPicks: () -> Void
    let inspect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if prompt.player == 1 {
                    Pill(text: t("duel.prompt.opponent"), tint: Theme.danger, systemImage: "person.fill")
                }
            }
            if let hint = prompt.hint, !isPhase {
                Text(fillSystemText(hint, []))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .disabled(model.busy)
        .opacity(model.busy ? 0.6 : 1)
        .id(prompt.id)
    }

    private var isPhase: Bool {
        switch prompt.kind {
        case .idle, .battle: true
        default: false
        }
    }

    private func respond(_ answer: DuelAnswer) {
        Task { await model.respond(answer) }
    }

    private var title: String {
        switch prompt.kind {
        case .idle, .battle:
            return t("duel.phases.\(state.phase.rawValue)")
        case .chain:
            return t("duel.prompt.CHAIN.title")
        case .yesNo(let text, let card):
            guard !text.isEmpty else { return t("duel.prompt.YESNO.title") }
            return fillSystemText(text, card.map { [model.name($0.code), t("duel.locations.\($0.location.rawValue)")] } ?? [])
        case .option:
            return t("duel.prompt.OPTION.title")
        case .selectCards(let mode, _, _, _, _, let sum, _):
            return mode == "SUM" ? t("duel.prompt.SELECT_CARDS.SUM", ["sum": sum ?? 0]) : t("duel.prompt.SELECT_CARDS.\(mode)")
        case .selectUnselect:
            return t("duel.prompt.SELECT_UNSELECT.title")
        case .place(_, let count, let disable):
            if disable { return t("duel.prompt.PLACE.disable") }
            return count > 1 ? t("duel.prompt.PLACE.titleMany", ["count": count]) : t("duel.prompt.PLACE.title")
        case .position:
            return t("duel.prompt.POSITION.title")
        case .announceNumber:
            return t("duel.prompt.ANNOUNCE_NUMBER.title")
        case .announce(let race, _, _):
            return t(race ? "duel.prompt.ANNOUNCE_RACE.title" : "duel.prompt.ANNOUNCE_ATTRIBUTE.title")
        case .announceCard:
            return t("duel.prompt.ANNOUNCE_CARD.title")
        case .sort:
            return t("duel.prompt.SORT.title")
        case .unknown:
            return t("duel.prompt.waiting")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch prompt.kind {
        case .idle(_, let canBattle, let canEnd):
            phaseButtons(hint: t("duel.prompt.IDLE"), main2: false, battle: canBattle, end: canEnd)
        case .battle(_, let canMain2, let canEnd):
            phaseButtons(hint: t("duel.prompt.BATTLE"), main2: canMain2, battle: false, end: canEnd)
        case .chain(let options, let forced):
            chain(options, forced: forced)
        case .yesNo:
            HStack(spacing: Spacing.s) {
                Button(t("duel.prompt.YESNO.yes")) { respond(DuelAnswer(yes: true)) }
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)
                Button(t("duel.prompt.YESNO.no")) { respond(DuelAnswer(yes: false)) }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
            }
        case .option(let options):
            VStack(spacing: Spacing.xs) {
                ForEach(options) { option in
                    Button { respond(DuelAnswer(index: option.index)) } label: {
                        Text(option.text).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.glass)
                }
            }
        case .selectCards(let mode, let cards, let must, let min, let max, let sum, let cancelable):
            DuelSelectCards(
                mode: mode, cards: cards, mustCards: must, min: min, max: max, sum: sum, cancelable: cancelable,
                model: model, respond: { respond($0) })
        case .selectUnselect(let selectable, let unselectable, let canFinish, let cancelable):
            selectUnselect(selectable, unselectable, canFinish: canFinish, cancelable: cancelable)
        case .place(_, let count, _):
            if count > 1 {
                HStack {
                    Text(t("duel.prompt.SELECT_CARDS.selected", ["count": "\(pickedCount)/\(count)"]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if pickedCount > 0 {
                        Button(t("duel.prompt.SORT.reset"), systemImage: "arrow.counterclockwise", action: resetPicks)
                            .labelStyle(.iconOnly)
                    }
                }
            }
        case .position(let code, let positions):
            HStack(spacing: Spacing.s) {
                ForEach(positions, id: \.self) { position in
                    Button { respond(DuelAnswer(position: position)) } label: {
                        VStack(spacing: Spacing.xs) {
                            DuelCardFace(code: position.isFaceDown ? 0 : code, model: model)
                                .frame(width: 44)
                                .rotationEffect(.degrees(position.isDefense ? 90 : 0))
                                .frame(height: 70)
                            Text(t("duel.positions.\(position.rawValue)"))
                                .font(.caption2.weight(.medium))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .tileSurface(padding: Spacing.s)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .announceNumber(let values):
            FlowLayout(spacing: Spacing.xs) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    Button("\(value)") { respond(DuelAnswer(index: index)) }
                        .buttonStyle(.glass)
                        .monospacedDigit()
                }
            }
        case .announce(let race, let choices, let count):
            DuelAnnounce(race: race, choices: choices, count: count, respond: { respond($0) })
        case .announceCard:
            DuelAnnounceCard(respond: { respond($0) })
        case .sort(let cards):
            DuelSort(cards: cards, model: model, respond: { respond($0) })
        case .unknown:
            ProgressView()
        }
    }

    private func phaseButtons(hint: String, main2: Bool, battle: Bool, end: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.s) {
                if battle {
                    Button(t("duel.controls.battle")) { respond(DuelAnswer(phase: "BATTLE")) }
                        .buttonStyle(.glass)
                }
                if main2 {
                    Button(t("duel.controls.main2")) { respond(DuelAnswer(phase: "MAIN2")) }
                        .buttonStyle(.glass)
                }
                if end {
                    Button(t("duel.controls.end")) { respond(DuelAnswer(phase: "END")) }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private func chain(_ options: [DuelChoiceCard], forced: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if forced {
                Text(t("duel.prompt.CHAIN.forced"))
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }
            ForEach(options) { option in
                HStack(spacing: Spacing.m) {
                    DuelCardFace(code: option.card.code, model: model)
                        .frame(width: 40)
                        .onTapGesture { inspect(option.card.code) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name(option.card.code))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let description = option.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(t("duel.actions.ACTIVATE"), systemImage: "checkmark") {
                        respond(DuelAnswer(index: option.index))
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glassProminent)
                }
                .tileSurface(padding: Spacing.s)
            }
            if !forced {
                Button { respond(DuelAnswer()) } label: {
                    Text(t("duel.prompt.CHAIN.pass")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func selectUnselect(
        _ selectable: [DuelChoiceCard], _ unselectable: [DuelChoiceCard], canFinish: Bool, cancelable: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if !unselectable.isEmpty {
                Text(t("duel.prompt.SELECT_UNSELECT.selected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DuelChoiceGrid(cards: unselectable, model: model, selected: Set(unselectable.map(\.index))) { choice in
                    respond(DuelAnswer(index: choice.index))
                }
            }
            DuelChoiceGrid(cards: selectable, model: model, selected: []) { choice in
                respond(DuelAnswer(index: choice.index))
            }
            if canFinish || cancelable {
                Button { respond(DuelAnswer()) } label: {
                    Text(canFinish ? t("duel.prompt.SELECT_UNSELECT.finish") : t("duel.prompt.SELECT_UNSELECT.cancel"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
            }
        }
    }
}

/// Textes système d'EDOPro à trous (« Activate the Trigger Effect of "%ls" from [%ls]? »).
func fillSystemText(_ text: String, _ values: [String]) -> String {
    var out = ""
    var remaining = values[...]
    var i = text.startIndex
    while i < text.endIndex {
        if text[i] == "%" {
            var j = text.index(after: i)
            if j < text.endIndex, text[j] == "l" { j = text.index(after: j) }
            if j < text.endIndex, text[j] == "s" || text[j] == "d" {
                out += remaining.popFirst() ?? ""
                i = text.index(after: j)
                continue
            }
        }
        out.append(text[i])
        i = text.index(after: i)
    }
    return out
        .replacingOccurrences(of: " []", with: "")
        .replacingOccurrences(of: "\"\"", with: "")
        .trimmingCharacters(in: .whitespaces)
}

// MARK: - Grille de choix

struct DuelChoiceGrid: View {
    let cards: [DuelChoiceCard]
    let model: DuelModel
    let selected: Set<Int>
    var order: [Int] = []
    let onTap: (DuelChoiceCard) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: Spacing.xs)], spacing: Spacing.xs) {
            ForEach(cards) { choice in
                let isOn = selected.contains(choice.index)
                VStack(spacing: 2) {
                    DuelCardFace(code: choice.card.code, model: model)
                        .overlay {
                            if isOn {
                                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if let rank = order.firstIndex(of: choice.index) {
                                Text("\(rank + 1)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.black)
                                    .frame(width: 18, height: 18)
                                    .background(Color.accentColor, in: .circle)
                                    .padding(2)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if choice.level > 0 {
                                Text("★\(choice.level)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 3)
                                    .background(.black.opacity(0.75), in: .rect(cornerRadius: 3))
                                    .padding(2)
                            }
                        }
                    Text(location(choice.card))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(.rect)
                .onTapGesture { onTap(choice) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(model.name(choice.card.code))
            }
        }
    }

    private func location(_ ref: DuelCardRef) -> String {
        let place = t("duel.locations.\(ref.location.rawValue)")
        return ref.controller == 1 ? "\(t("duel.board.opponent")) · \(place)" : place
    }
}

// MARK: - Sélection de cartes

private struct DuelSelectCards: View {
    let mode: String
    let cards: [DuelChoiceCard]
    let mustCards: [DuelChoiceCard]
    let min: Int
    let max: Int
    let sum: Int?
    let cancelable: Bool
    let model: DuelModel
    let respond: (DuelAnswer) -> Void

    @State private var picked: [Int] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                if mode == "CARD" { Text(range) }
                Spacer()
                Text(counter).monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !mustCards.isEmpty {
                Text(t("duel.prompt.SELECT_CARDS.always"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DuelChoiceGrid(cards: mustCards, model: model, selected: Set(mustCards.map(\.index))) { _ in }
            }
            DuelChoiceGrid(cards: cards, model: model, selected: Set(picked)) { choice in
                if let i = picked.firstIndex(of: choice.index) {
                    picked.remove(at: i)
                } else {
                    picked.append(choice.index)
                }
            }
            HStack(spacing: Spacing.s) {
                Button { respond(DuelAnswer(indices: picked)) } label: {
                    Text(t("duel.prompt.SELECT_CARDS.confirm")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(!valid)
                if cancelable {
                    Button(t("duel.prompt.SELECT_CARDS.cancel")) { respond(DuelAnswer()) }
                        .buttonStyle(.glass)
                }
            }
        }
    }

    private func values(_ indices: [Int]) -> [Int] {
        indices.compactMap { i in cards.first { $0.index == i }?.value }
    }

    private var reachable: Set<Int> {
        var sums: Set<Int> = [0]
        for v in mustCards.compactMap(\.value) + values(picked) {
            let low = v & 0xffff
            let high = v >> 16
            var next: Set<Int> = []
            for s in sums {
                next.insert(s + low)
                if high > 0 { next.insert(s + high) }
            }
            sums = next
        }
        return sums
    }

    private var valid: Bool {
        switch mode {
        case "CARD":
            return picked.count >= min && picked.count <= max
        case "TRIBUTE":
            let total = values(picked).reduce(0) { $0 + Swift.max(1, $1) }
            return !picked.isEmpty && total >= min && picked.count <= max
        default:
            return reachable.contains { $0 >= (sum ?? 0) } && picked.count >= Swift.max(0, min - mustCards.count)
        }
    }

    private var range: String {
        if min == max { return t("duel.prompt.range.exact", ["count": min]) }
        if min == 0 { return t("duel.prompt.range.upTo", ["max": max]) }
        return t("duel.prompt.range.between", ["min": min, "max": max])
    }

    private var counter: String {
        if mode == "SUM" {
            return t("duel.prompt.SELECT_CARDS.total", ["total": reachable.max() ?? 0, "sum": sum ?? 0])
        }
        return t("duel.prompt.SELECT_CARDS.selected", ["count": "\(picked.count)"])
    }
}

// MARK: - Ordre, déclarations

private struct DuelSort: View {
    let cards: [DuelChoiceCard]
    let model: DuelModel
    let respond: (DuelAnswer) -> Void
    @State private var clicked: [Int] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(t("duel.prompt.SORT.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            DuelChoiceGrid(cards: cards, model: model, selected: Set(clicked), order: clicked) { choice in
                if !clicked.contains(choice.index) { clicked.append(choice.index) }
            }
            HStack(spacing: Spacing.s) {
                Button { respond(DuelAnswer(order: ranks)) } label: {
                    Text(t("duel.prompt.SORT.confirm")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(clicked.count != cards.count)
                if clicked.isEmpty {
                    Button(t("duel.prompt.SORT.keep")) { respond(DuelAnswer()) }
                        .buttonStyle(.glass)
                } else {
                    Button(t("duel.prompt.SORT.reset")) { clicked = [] }
                        .buttonStyle(.glass)
                }
            }
        }
    }

    /// ranks[i] = rang voulu pour la carte i
    private var ranks: [Int] {
        var out = Array(repeating: 0, count: cards.count)
        for (rank, index) in clicked.enumerated() where index < out.count { out[index] = rank }
        return out
    }
}

private struct DuelAnnounce: View {
    let race: Bool
    let choices: [String]
    let count: Int
    let respond: (DuelAnswer) -> Void
    @State private var picked: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(t("duel.prompt.choose", ["count": count]))
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: Spacing.xs) {
                ForEach(choices, id: \.self) { value in
                    let isOn = picked.contains(value)
                    Button(t(race ? "duel.races.\(value)" : "duel.attributes.\(value)")) {
                        if isOn {
                            picked.removeAll { $0 == value }
                        } else {
                            picked = Array(((count == 1 ? [] : picked) + [value]).suffix(count))
                        }
                    }
                    .buttonStyle(.glass)
                    .tint(isOn ? .accentColor : nil)
                    .font(.caption.weight(isOn ? .bold : .regular))
                }
            }
            Button { respond(DuelAnswer(values: picked)) } label: {
                Text(t("duel.prompt.confirm")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(picked.count != count)
        }
    }
}

private struct DuelAnnounceCard: View {
    let respond: (DuelAnswer) -> Void
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var results: [CardSummary] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            TextField(t("duel.prompt.ANNOUNCE_CARD.search"), text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: Spacing.xs)], spacing: Spacing.xs) {
                ForEach(results) { card in
                    CardArt(card: card, width: .thumb)
                        .onTapGesture { respond(DuelAnswer(cardId: card.id)) }
                }
            }
        }
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = (try? await app.api.searchCards(CardSearchQuery(q: text, pageSize: 12)).items) ?? results
        }
    }
}
