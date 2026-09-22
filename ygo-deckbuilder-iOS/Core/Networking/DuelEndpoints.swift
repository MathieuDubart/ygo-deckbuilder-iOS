import Foundation

/// Simulateur de duel (cf. apps/api/src/modules/duel/duel.controller.ts).
extension APIClient {
    func duelEngine() async throws -> DuelEngineStatus { try await get("duels/engine") }

    func createDuel(_ body: CreateDuelBody) async throws -> DuelState { try await send(.post, "duels", body: body) }

    func duel(_ id: String) async throws -> DuelState { try await get("duels/\(id)") }

    func respond(duel id: String, promptId: Int, _ answer: DuelAnswer) async throws -> DuelState {
        try await send(.post, "duels/\(id)/respond", body: DuelResponseBody(promptId: promptId, answer: answer))
    }

    func updateDuel(_ id: String, chainPrompts: DuelChainPrompts) async throws -> DuelState {
        try await send(.patch, "duels/\(id)", body: DuelSettingsBody(chainPrompts: chainPrompts))
    }

    func deleteDuel(_ id: String) async throws { try await perform(.delete, "duels/\(id)") }
}
