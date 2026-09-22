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
            apply(resumed, reset: true)
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
                self.apply(next, reset: true)
                self.saveSetup()
            } catch {
                self.clear()
                self.error = error.localizedDescription
            }
        }
    }

    func respond(_ answer: DuelAnswer) async {
        await run {
            guard let state = self.state, let prompt = state.prompt else { return }
            do {
                self.apply(try await self.api.respond(duel: state.id, promptId: prompt.id, answer))
            } catch let error as APIError where error.status == 404 {
                self.clear()
                self.error = error.message
            } catch {
                // Réponse refusée ou invite périmée : on se resynchronise
                if let fresh = try? await self.api.duel(state.id) { self.apply(fresh) }
                self.error = error.localizedDescription
            }
        }
    }

    func setChainPrompts(_ mode: DuelChainPrompts) async {
        await run {
            guard let state = self.state else { return }
            do {
                self.apply(try await self.api.updateDuel(state.id, chainPrompts: mode))
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

    private func apply(_ next: DuelState, reset: Bool = false) {
        state = next
        log = Array(((reset ? [] : log) + next.events).suffix(Self.logLimit))
        var merged = reset ? [:] : cards
        for (key, summary) in next.cards {
            if let code = Int(key) { merged[code] = summary }
        }
        cards = merged
        UserDefaults.standard.set(next.id, forKey: Self.duelKey)
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
