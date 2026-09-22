import Foundation
import Observation

/// État local du deck builder : édition instantanée, validation live (règles partagées) et
/// sauvegarde automatique 800 ms après la dernière modification (cf. use-deck-builder.ts).
@Observable
final class DeckBuilderModel {
    struct Entry: Identifiable, Hashable {
        var card: CardSummary
        var zone: DeckZone
        var quantity: Int
        var owned: Int
        var id: String { "\(zone.rawValue):\(card.id)" }
    }

    struct MissingCard: Identifiable {
        let card: CardSummary
        let required: Int
        let owned: Int
        var missing: Int { required - owned }
        var id: Int { card.id }
    }

    enum SaveStatus: Equatable { case saved, dirty, saving, error }

    let deckId: String
    private(set) var name: String
    private(set) var format: DeckFormat
    private(set) var entries: [String: Entry] = [:]
    private(set) var status: SaveStatus = .saved

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var version = 0
    @ObservationIgnored var onSaved: (() -> Void)?

    init(deck: Deck, api: APIClient) {
        deckId = deck.id
        name = deck.name
        format = deck.format
        self.api = api
        for c in deck.cards {
            let entry = Entry(card: c.card, zone: c.zone, quantity: c.quantity, owned: c.ownedQuantity)
            entries[entry.id] = entry
        }
    }

    var isOCG: Bool { format == .ocg }

    // MARK: - Lecture

    func cards(in zone: DeckZone) -> [Entry] {
        entries.values
            .filter { $0.zone == zone }
            .sorted {
                ($0.card.category.sortOrder, -($0.card.level ?? 0), $0.card.name)
                    < ($1.card.category.sortOrder, -($1.card.level ?? 0), $1.card.name)
            }
    }

    func count(_ zone: DeckZone) -> Int {
        entries.values.filter { $0.zone == zone }.reduce(0) { $0 + $1.quantity }
    }

    func quantity(of cardId: Int, in zone: DeckZone) -> Int {
        entries["\(zone.rawValue):\(cardId)"]?.quantity ?? 0
    }

    func totalCopies(of cardId: Int) -> Int {
        DeckZone.allCases.reduce(0) { $0 + quantity(of: cardId, in: $1) }
    }

    /// Exemplaires autorisés (banlist TCG, sauf format OCG).
    func limit(for card: CardSummary) -> Int {
        isOCG ? DeckRules.maxCopies : DeckRules.maxCopies(for: card.banTcg)
    }

    var issues: [DeckIssue] {
        DeckRules.validate(entries.values.map {
            DeckRules.Entry(
                cardId: $0.card.id, zone: $0.zone, quantity: $0.quantity,
                isExtraDeckMonster: $0.card.isExtraDeck, banStatus: isOCG ? nil : $0.card.banTcg)
        })
    }

    var missing: [MissingCard] {
        var need: [Int: MissingCard] = [:]
        for e in entries.values {
            let cur = need[e.card.id]
            need[e.card.id] = MissingCard(card: e.card, required: (cur?.required ?? 0) + e.quantity, owned: e.owned)
        }
        return need.values.filter { $0.required > $0.owned }.sorted { $0.card.name < $1.card.name }
    }

    var missingCost: Double {
        missing.reduce(0) { $0 + Double($1.missing) * ($1.card.priceCardmarket ?? 0) }
    }

    func cardName(_ id: Int) -> String {
        entries.values.first { $0.card.id == id }?.card.name ?? "#\(id)"
    }

    /// Cartes de la liste, pour le guide de jeu.
    var guideCards: [DeckCardEntry] {
        entries.values.map { DeckCardEntry(cardId: $0.card.id, zone: $0.zone, quantity: $0.quantity) }
    }

    // MARK: - Édition

    /// Ajoute 1 exemplaire. Zone par défaut : EXTRA pour les monstres de l'Extra Deck, sinon MAIN.
    /// Renvoie la raison du refus, ou nil.
    @discardableResult
    func add(_ card: CardSummary, to zone: DeckZone? = nil) -> String? {
        let target = zone ?? (card.isExtraDeck ? .extra : .main)
        if target == .main && card.isExtraDeck { return t("deckBuilder.add.extraDeckMonster") }
        if target == .extra && !card.isExtraDeck { return t("deckBuilder.add.notExtraDeck") }
        let allowed = limit(for: card)
        if totalCopies(of: card.id) >= allowed { return t("deckBuilder.add.maxCopies", ["limit": allowed]) }
        if count(target) >= DeckRules.range(target).upperBound {
            return t("deckBuilder.add.zoneFull", ["zone": t("common.zones.\(target.rawValue)")])
        }
        let key = "\(target.rawValue):\(card.id)"
        var entry = entries[key] ?? Entry(card: card, zone: target, quantity: 0, owned: card.owned)
        entry.quantity += 1
        if let owned = card.ownedQuantity { entry.owned = owned }
        entries[key] = entry
        scheduleSave()
        return nil
    }

    func removeOne(_ cardId: Int, from zone: DeckZone) {
        let key = "\(zone.rawValue):\(cardId)"
        guard var entry = entries[key] else { return }
        if entry.quantity <= 1 {
            entries[key] = nil
        } else {
            entry.quantity -= 1
            entries[key] = entry
        }
        scheduleSave()
    }

    func rename(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return }
        name = String(trimmed.prefix(80))
        Task { try? await api.updateDeck(deckId, UpdateDeckBody(name: name)); onSaved?() }
    }

    func setFormat(_ newFormat: DeckFormat) {
        guard newFormat != format else { return }
        format = newFormat
        Task { try? await api.updateDeck(deckId, UpdateDeckBody(format: newFormat)); onSaved?() }
    }

    /// Met à jour les quantités possédées (après un ajout à la collection).
    func refreshOwned(from deck: Deck) {
        for c in deck.cards {
            let key = "\(c.zone.rawValue):\(c.cardId)"
            if var entry = entries[key] {
                entry.owned = c.ownedQuantity
                entries[key] = entry
            }
        }
    }

    // MARK: - Sauvegarde

    private func scheduleSave() {
        status = .dirty
        version += 1
        let current = version
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self else { return }
            await self.save(version: current)
        }
    }

    func retrySave() {
        scheduleSave()
    }

    /// Sauvegarde immédiate (en quittant l'écran).
    func flush() async {
        guard status == .dirty || status == .error else { return }
        saveTask?.cancel()
        await save(version: version)
    }

    private func save(version current: Int) async {
        status = .saving
        let cards = entries.values.map { DeckCardEntry(cardId: $0.card.id, zone: $0.zone, quantity: $0.quantity) }
        do {
            try await api.updateDeck(deckId, UpdateDeckBody(cards: cards))
            if current == version { status = .saved }
            onSaved?()
        } catch {
            if current == version { status = .error }
        }
    }
}
