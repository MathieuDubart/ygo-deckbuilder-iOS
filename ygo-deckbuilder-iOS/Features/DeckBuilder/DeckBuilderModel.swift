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

    /// Le statut banlist qui s'applique à cette carte, selon le format du deck.
    func banStatus(of card: CardSummary) -> String? {
        DeckRules.banStatus(of: card, format: format)
    }

    /// Exemplaires autorisés pour cette carte, selon le format du deck.
    func limit(for card: CardSummary) -> Int {
        DeckRules.maxCopies(for: banStatus(of: card))
    }

    /**
     Pourquoi cette carte ne peut pas être ajoutée, ou `nil` si elle peut. Le picker s'en sert
     pour éteindre la vignette AVANT le geste : apprendre qu'une carte est interdite au moment
     où on la touche, c'est l'apprendre trop tard.
     */
    func blockedReason(for card: CardSummary) -> String? {
        let status = BanStatus(label: banStatus(of: card))
        if status == .forbidden { return t("cards.ban.FORBIDDEN") }
        let count = totalCopies(of: card.id)
        guard count >= limit(for: card) else { return nil }
        // Dire ce qui bloque, pas la règle : « déjà 3 » se comprend, « maximum 3 » laisse
        // croire qu'on énonce une limite théorique alors qu'on vient de la toucher.
        guard let status else { return t("deckBuilder.add.atLimit", ["count": count]) }
        return t(
            "deckBuilder.add.atLimitBan",
            ["status": t("cards.ban.\(status.messageKey)"), "count": count])
    }

    /// La decklist dans la forme que comprennent les règles partagées.
    private var forValidation: [DeckRules.Entry] {
        entries.values.map {
            DeckRules.Entry(
                cardId: $0.card.id, zone: $0.zone, quantity: $0.quantity,
                isExtraDeckMonster: $0.card.isExtraDeck, banStatus: banStatus(of: $0.card))
        }
    }

    var issues: [DeckIssue] { DeckRules.validate(forValidation) }

    /// Les exemplaires à retirer pour repasser la banlist, vide si la liste est légale.
    var banlistFixes: [DeckRules.Fix] { DeckRules.fixes(forValidation) }

    /**
     Applique le correctif de banlist : on retire, rien d'autre. Renvoie le nombre
     d'exemplaires retirés, pour pouvoir le dire à l'écran.
     */
    @discardableResult
    func applyBanlistFixes() -> Int {
        let fixes = banlistFixes
        guard !fixes.isEmpty else { return 0 }
        for fix in fixes {
            let key = "\(fix.zone.rawValue):\(fix.cardId)"
            guard var entry = entries[key] else { continue }
            entry.quantity -= fix.remove
            if entry.quantity > 0 { entries[key] = entry } else { entries[key] = nil }
        }
        scheduleSave()
        return fixes.reduce(0) { $0 + $1.remove }
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
        if let blocked = blockedReason(for: card) { return blocked }
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
        Task { _ = try? await api.updateDeck(deckId, UpdateDeckBody(name: name)); onSaved?() }
    }

    func setFormat(_ newFormat: DeckFormat) {
        guard newFormat != format else { return }
        format = newFormat
        Task { _ = try? await api.updateDeck(deckId, UpdateDeckBody(format: newFormat)); onSaved?() }
    }

    /// Met à jour les quantités possédées (après un ajout à la collection).
    func refreshOwned(from deck: Deck) {
        update(from: deck) { entry, c in entry.owned = c.ownedQuantity }
    }

    /**
     Recharge les cartes elles-mêmes, pas seulement les quantités possédées. Les statuts de
     banlist vivent DANS la carte : relire la liste côté serveur ne change rien à l'écran tant
     que les `CardSummary` du deck restent ceux d'avant.
     */
    func refreshCards(from deck: Deck) {
        update(from: deck) { entry, c in
            entry.card = c.card
            entry.owned = c.ownedQuantity
        }
    }

    private func update(from deck: Deck, _ apply: (inout Entry, DeckCard) -> Void) {
        for c in deck.cards {
            let key = "\(c.zone.rawValue):\(c.cardId)"
            guard var entry = entries[key] else { continue }
            apply(&entry, c)
            entries[key] = entry
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
