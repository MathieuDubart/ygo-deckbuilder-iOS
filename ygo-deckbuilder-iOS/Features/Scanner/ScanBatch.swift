import Foundation
import Observation

/// Une carte en attente d'être ajoutée à la collection : ce que le scan a trouvé, modifiable
/// avant validation.
@Observable
final class ScanDraft: Identifiable {
    let id = UUID()
    let card: CardSummary
    /// Impressions connues de la carte (pour le sélecteur d'édition).
    let prints: [CardPrint]
    /// Code lu par la caméra, nil si la carte a été ajoutée à la main.
    let code: String?

    var printId: String?
    var quantity: Int
    var condition: CardCondition
    var language: CardLanguage
    var firstEdition: Bool

    init(
        card: CardSummary,
        prints: [CardPrint],
        code: String? = nil,
        printId: String? = nil,
        quantity: Int = 1,
        condition: CardCondition = .nearMint,
        language: CardLanguage = L10n.shared.current.cardLanguage,
        firstEdition: Bool = false
    ) {
        self.card = card
        self.prints = prints
        self.code = code
        self.printId = printId
        self.quantity = quantity
        self.condition = condition
        self.language = language
        self.firstEdition = firstEdition
    }

    /// Édition choisie, pour l'affichage de la ligne.
    var print: CardPrint? { prints.first { $0.id == printId } }

    var subtitle: String {
        if let print { return "\(print.printCode) — \(print.rarity)" }
        return code ?? card.type
    }
}

/// File des cartes scannées. On scanne en continu, on vérifie à la fin.
@Observable
final class ScanBatch {
    private(set) var drafts: [ScanDraft] = []
    /// Dernière carte ajoutée, pour l'afficher sous le viseur.
    private(set) var last: ScanDraft?
    private(set) var saving = false
    /// Nombre de lignes déjà envoyées pendant la validation.
    private(set) var saved = 0
    private(set) var failures: [String] = []

    var isEmpty: Bool { drafts.isEmpty }
    var totalCopies: Int { drafts.reduce(0) { $0 + $1.quantity } }

    /// Ajoute une carte. Le même code avec la même édition = un exemplaire de plus,
    /// ce qui correspond à scanner deux copies de la même carte à la suite.
    @discardableResult
    func add(card: CardSummary, prints: [CardPrint], code: String? = nil,
             printId: String? = nil, language: CardLanguage? = nil) -> ScanDraft {
        if let code, let existing = drafts.first(where: { $0.code == code && $0.printId == printId }) {
            existing.quantity += 1
            last = existing
            return existing
        }
        let draft = ScanDraft(
            card: card, prints: prints, code: code, printId: printId,
            language: language ?? L10n.shared.current.cardLanguage)
        drafts.append(draft)
        last = draft
        return draft
    }

    func remove(_ draft: ScanDraft) {
        drafts.removeAll { $0.id == draft.id }
        if last?.id == draft.id { last = drafts.last }
    }

    /// `remove(atOffsets:)` vient de SwiftUI : on reste sur Foundation comme les autres modèles.
    func remove(atOffsets offsets: IndexSet) {
        let kept = drafts.enumerated().filter { !offsets.contains($0.offset) }.map { $0.element }
        let keptIds = Set(kept.map(\.id))
        drafts = kept
        if let last, !keptIds.contains(last.id) { self.last = drafts.last }
    }

    /// Annule le dernier ajout (un exemplaire, puis la ligne).
    func undoLast() {
        guard let draft = last else { return }
        if draft.quantity > 1 {
            draft.quantity -= 1
        } else {
            remove(draft)
        }
    }

    /// Envoie toute la file à la collection. Renvoie `true` si tout est passé.
    func commit(api: APIClient) async -> Bool {
        guard !saving else { return false }
        saving = true
        saved = 0
        failures = []
        defer { saving = false }
        // Les lignes passées sortent de la file au fur et à mesure : réessayer après une
        // erreur ne renvoie que ce qui manque, jamais un doublon.
        var done: Set<UUID> = []
        for draft in drafts {
            do {
                try await api.addToCollection(AddCollectionItemBody(
                    cardId: draft.card.id, printId: draft.printId, quantity: draft.quantity,
                    condition: draft.condition, language: draft.language,
                    firstEdition: draft.firstEdition))
                saved += 1
                done.insert(draft.id)
            } catch {
                failures.append("\(draft.card.name) — \(error.localizedDescription)")
            }
        }
        drafts.removeAll { done.contains($0.id) }
        if let last, done.contains(last.id) { self.last = drafts.last }
        return failures.isEmpty
    }
}
