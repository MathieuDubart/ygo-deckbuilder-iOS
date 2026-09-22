import Foundation
import Observation

/// Duel en cours : état renvoyé par l'API, journal et cartes citées accumulés au fil des
/// réponses. L'identifiant et la dernière configuration sont gardés → on reprend le duel au
/// retour dans l'app, et « Recommencer » rejoue la même préparation.
@Observable
final class DuelModel {
    private static let duelKey = "duel.current"
    private static let setupKey = "duel.setup"
    /// Le journal garde les derniers événements seulement
    private static let logLimit = 500

    private(set) var engine: Loadable<DuelEngineStatus> = .idle
    private(set) var state: DuelState?
    private(set) var log: [DuelEvent] = []
    private(set) var cards: [Int: CardSummary] = [:]
    private(set) var busy = false
    private(set) var resuming = true
    var setup: CreateDuelBody
    var error: String?

    // Replay : le terrain reste figé pendant que les événements passent un par un
    private(set) var playing = false
    private(set) var fx: DuelFxFrame?
    /// PV affichés pendant le replay (les dégâts défilent avant le nouvel état)
    private(set) var lpOverride: [Int]?
    @ObservationIgnored private var skipping = false
    @ObservationIgnored private var frameCounter = 0

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) {
        self.api = api
        if let data = UserDefaults.standard.data(forKey: Self.setupKey),
           let saved = try? JSONDecoder().decode(CreateDuelBody.self, from: data) {
            setup = saved
        } else {
            setup = CreateDuelBody()
        }
    }

    // MARK: - Chargement

    /// Données du moteur (prêtes ou en cours de téléchargement), puis reprise du duel en cours.
    func load() async {
        engine = await .fetch(engine) { try await api.duelEngine() }
        guard resuming else { return }
        defer { resuming = false }
        guard let id = UserDefaults.standard.string(forKey: Self.duelKey) else { return }
        if let resumed = try? await api.duel(id) {
            await apply(resumed, mode: .resume)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.duelKey)
        }
    }

    // MARK: - Actions

    func start() async {
        await run {
            if let previous = self.state?.id { try? await self.api.deleteDuel(previous) }
            do {
                let next = try await self.api.createDuel(self.setup)
                self.saveSetup()
                await self.apply(next, mode: .start)
            } catch {
                self.clear()
                self.error = error.localizedDescription
            }
        }
    }

    func respond(_ answer: DuelAnswer) async {
        await run {
            guard let state = self.state, let prompt = state.prompt else { return }
            DuelSound.shared.play(.select)
            do {
                await self.apply(try await self.api.respond(duel: state.id, promptId: prompt.id, answer))
            } catch let error as APIError where error.status == 404 {
                self.clear()
                self.error = error.message
            } catch {
                // Réponse refusée ou invite périmée : on se resynchronise
                if let fresh = try? await self.api.duel(state.id) { await self.apply(fresh, mode: .resume) }
                self.error = error.localizedDescription
            }
        }
    }

    func setChainPrompts(_ mode: DuelChainPrompts) async {
        await run {
            guard let state = self.state else { return }
            do {
                await self.apply(try await self.api.updateDuel(state.id, chainPrompts: mode))
                self.setup.chainPrompts = mode
                self.saveSetup()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func leave() async {
        await run {
            if let id = self.state?.id { try? await self.api.deleteDuel(id) }
            self.clear()
        }
    }

    // MARK: - Aides

    /// Coupe le replay en cours : les événements restants vont directement au journal.
    func skip() {
        if playing { skipping = true }
    }

    func card(_ code: Int) -> CardSummary? { code == 0 ? nil : cards[code] }

    func name(_ code: Int) -> String {
        code == 0 ? t("duel.log.hidden") : (cards[code]?.name ?? "#\(code)")
    }

    private func run(_ work: @escaping () async -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await work()
    }

    private enum ApplyMode { case resume, start, step }

    /// Nouvel état de l'API. `resume` : affichage direct ; `start` : bandeau « Duel ! » puis
    /// replay des premiers événements ; sinon replay depuis l'état affiché, puis le nouvel état.
    private func apply(_ next: DuelState, mode: ApplyMode = .step) async {
        var merged = mode == .step ? cards : [:]
        for (key, summary) in next.cards {
            if let code = Int(key) { merged[code] = summary }
        }
        cards = merged
        UserDefaults.standard.set(next.id, forKey: Self.duelKey)

        switch mode {
        case .resume:
            state = next
            log = Array(next.events.suffix(Self.logLimit))
        case .start:
            // L'adversaire a déjà joué : on part d'un terrain vide pour ne pas dévoiler la suite
            let acted = next.events.contains { event in
                switch event.kind {
                case .summon, .set, .activate: true
                default: false
                }
            }
            state = acted ? next.emptied() : next
            log = []
            let settings = DuelFxSettings.shared
            let banner = settings.speed.scaled(1200)
            if banner > 0 {
                DuelSound.shared.play(.turn)
                frameCounter += 1
                fx = DuelFxFrame(content: .start, id: frameCounter, duration: banner, shake: false)
                playing = true
                await pause(banner)
            }
            await replay(next.events, from: Self.lifePointsBefore(next))
            state = next
        case .step:
            await replay(next.events, from: (state ?? next).players.map(\.lp))
            state = next
        }
    }

    /// PV avant les événements d'une réponse (les PV finaux, moins les dégâts, plus les soins).
    private static func lifePointsBefore(_ state: DuelState) -> [Int] {
        var points = state.players.map(\.lp)
        for event in state.events {
            switch event.kind {
            case .damage(let player, let amount, _) where player < points.count: points[player] += amount
            case .recover(let player, let amount) where player < points.count: points[player] -= amount
            default: break
            }
        }
        return points
    }

    private func replay(_ events: [DuelEvent], from start: [Int]) async {
        let settings = DuelFxSettings.shared
        var points = start
        skipping = skipping || settings.speed == .off
        playing = true
        lpOverride = points
        for event in events {
            log = Array((log + [event]).suffix(Self.logLimit))
            switch event.kind {
            case .damage(let player, let amount, _) where player < points.count:
                points[player] = Swift.max(0, points[player] - amount)
                lpOverride = points
            case .recover(let player, let amount) where player < points.count:
                points[player] += amount
                lpOverride = points
            default:
                break
            }
            if skipping { continue }
            let beat = DuelBeat(event)
            let duration = settings.speed.scaled(beat.duration)
            guard duration > 0 else { continue }
            if let sfx = beat.sfx { DuelSound.shared.play(sfx) }
            DuelHaptics.play(event)
            frameCounter += 1
            fx = DuelFxFrame(content: .event(event), id: frameCounter, duration: duration, shake: beat.shake)
            await pause(duration)
        }
        fx = nil
        lpOverride = nil
        playing = false
        skipping = false
    }

    /// Attente interruptible par « Passer ».
    private func pause(_ ms: Int) async {
        var left = ms
        while left > 0, !skipping {
            try? await Task.sleep(for: .milliseconds(Swift.min(40, left)))
            left -= 40
        }
    }

    private func clear() {
        state = nil
        log = []
        cards = [:]
        UserDefaults.standard.removeObject(forKey: Self.duelKey)
    }

    private func saveSetup() {
        if let data = try? JSONEncoder().encode(setup) {
            UserDefaults.standard.set(data, forKey: Self.setupKey)
        }
    }
}

/// Plan affiché par la scène du replay.
struct DuelFxFrame: Equatable {
    enum Content: Equatable {
        case start
        case event(DuelEvent)
    }

    let content: Content
    /// Change à chaque plan (relance les animations)
    let id: Int
    /// Durée réelle du plan (ms)
    let duration: Int
    let shake: Bool
}

extension DuelState {
    /// Le duel avant la première action : mains et Terrain vides.
    func emptied() -> DuelState {
        DuelState(
            id: id, turn: turn, turnPlayer: turnPlayer, phase: phase,
            players: players.map { p in
                DuelPlayer(
                    lp: p.lp, deckCount: p.deckCount, extraCount: p.extraCount, hand: [],
                    monsters: p.monsters.map { _ in nil }, spells: p.spells.map { _ in nil },
                    grave: [], banished: [], extra: p.extra)
            },
            chain: [], prompt: nil, events: [], cards: cards, opponentControl: opponentControl,
            chainPrompts: chainPrompts, finished: finished)
    }
}
