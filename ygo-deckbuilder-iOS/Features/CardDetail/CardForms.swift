import SwiftUI

/// Ajout à la collection : impression, quantité, état, langue, 1re édition.
struct AddToCollectionSection: View {
    let card: CardDetail
    var printHint: String?

    @Environment(AppState.self) private var app
    @State private var printId: String?
    @State private var quantity = 1
    @State private var condition: CardCondition = .nearMint
    @State private var language: CardLanguage = L10n.shared.current.cardLanguage
    @State private var firstEdition = false
    @State private var saving = false
    @State private var message: (text: String, ok: Bool)?

    var body: some View {
        GroupBox {
            VStack(spacing: Spacing.m) {
                PrintPicker(prints: card.prints, selection: $printId)
                Stepper(value: $quantity, in: 1...99) {
                    LabeledContent(t("cards.collectionForm.quantity"), value: "\(quantity)")
                }
                Picker(t("cards.collectionForm.condition"), selection: $condition) {
                    ForEach(CardCondition.allCases) { Text(t("cards.conditions.\($0.rawValue)")).tag($0) }
                }
                Picker(t("cards.collectionForm.language"), selection: $language) {
                    ForEach(CardLanguage.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle(t("cards.collectionForm.firstEdition"), isOn: $firstEdition)

                Button {
                    Task { await add() }
                } label: {
                    Label(t("common.actions.add"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(saving)

                if let message {
                    Text(message.text)
                        .font(.footnote)
                        .foregroundStyle(message.ok ? Theme.success : Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } label: {
            Label(t("cards.collectionForm.title"), systemImage: "square.stack.3d.up")
        }
        .task(id: card.id) { applyHint() }
    }

    /// Code scanné (SDBE-FR001) → impression correspondante et langue FR.
    private func applyHint() {
        guard let hint = printHint.flatMap(PrintCode.init) else { return }
        printId = card.prints.first { hint.matches($0.printCode) }?.id
        if let lang = hint.language { language = lang }
    }

    private func add() async {
        saving = true
        defer { saving = false }
        do {
            try await app.api.addToCollection(AddCollectionItemBody(
                cardId: card.id, printId: printId, quantity: quantity, condition: condition,
                language: language, firstEdition: firstEdition))
            message = (t("cards.collectionForm.success", ["count": quantity]), true)
            app.collectionChanged()
        } catch {
            message = (error.localizedDescription, false)
        }
    }
}

/// « Je la cherche » : impression visée, quantité, budget max.
struct AddToWishlistSection: View {
    let card: CardDetail

    @Environment(AppState.self) private var app
    @State private var expanded = false
    @State private var printId: String?
    @State private var quantity = 1
    @State private var maxPrice = ""
    @State private var saving = false
    @State private var message: (text: String, ok: Bool)?

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: Spacing.m) {
                    PrintPicker(prints: card.prints, selection: $printId, label: t("cards.wishlistForm.print"))
                    Stepper(value: $quantity, in: 1...3) {
                        LabeledContent(t("cards.wishlistForm.quantity"), value: "\(quantity)")
                    }
                    LabeledContent(t("cards.wishlistForm.maxPrice")) {
                        TextField("—", text: $maxPrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                    Button {
                        Task { await add() }
                    } label: {
                        Label(t("cards.wishlistForm.open"), systemImage: "heart")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(saving)

                    if let message {
                        Text(message.text)
                            .font(.footnote)
                            .foregroundStyle(message.ok ? Theme.success : Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, Spacing.m)
            } label: {
                Label(t("cards.wishlistForm.title"), systemImage: "heart")
            }
        }
    }

    private func add() async {
        saving = true
        defer { saving = false }
        do {
            try await app.api.addToWishlist(AddWishlistBody(
                cardId: card.id, printId: printId, quantity: quantity,
                maxPrice: Double(maxPrice.replacingOccurrences(of: ",", with: "."))))
            message = (t("cards.wishlistForm.success"), true)
            app.wishlistChanged()
        } catch {
            message = (error.localizedDescription, false)
        }
    }
}

/// Choix d'une impression (ou « non précisée »).
struct PrintPicker: View {
    let prints: [CardPrint]
    @Binding var selection: String?
    var label: String = t("cards.collectionForm.print")

    var body: some View {
        Picker(label, selection: $selection) {
            Text(t("cards.detail.printUnspecified")).tag(String?.none)
            ForEach(prints) { print in
                Text("\(print.printCode) — \(print.rarity)").tag(String?.some(print.id))
            }
        }
        .pickerStyle(.navigationLink)
    }
}
