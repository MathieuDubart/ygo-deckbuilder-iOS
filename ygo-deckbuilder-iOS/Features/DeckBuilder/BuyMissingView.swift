import SwiftUI
import UIKit

/**
 Acheter les cartes qui manquent au deck.

 Cardmarket n'a pas de panier qu'on puisse pré-remplir par une URL — l'ajout passe par une
 session connectée, carte par carte — donc on produit le texte que leur liste de souhaits
 avale d'un coup, et c'est leur assistant d'achat qui répartit ensuite la commande entre les
 vendeurs les moins chers. Les liens carte par carte restent là pour qui n'en veut qu'une.
 */
struct BuyMissingView: View {
    let missing: [DeckBuilderModel.MissingCard]

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var text: String {
        Cardmarket.wantsListText(
            missing.map { .init(nameEn: $0.card.marketName, quantity: $0.missing) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    steps

                    Text(text)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.s)
                        .background(.fill.tertiary, in: .rect(cornerRadius: Radius.s, style: .continuous))

                    actions

                    // Dit franchement ce que la liste ne porte pas, plutôt que de le laisser
                    // découvrir au moment où une ligne est rejetée.
                    Text(t("deckBuilder.missing.buy.noEditionHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        SectionHeader(t("deckBuilder.missing.buy.oneByOne"))
                        ForEach(missing) { card in
                            row(card)
                        }
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
            .navigationTitle(t("deckBuilder.missing.buy.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.actions.close")) { dismiss() }
                }
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(["step1", "step2", "step3"].enumerated()), id: \.element) { index, key in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text("\(index + 1).")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(t("deckBuilder.missing.buy.\(key)"))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.s) {
            Button {
                UIPasteboard.general.string = text
                copied = true
                // Le libellé redescend, sinon le bouton annonce « copié » jusqu'à la
                // fermeture de la feuille et ne dit plus rien du dernier appui.
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Label(
                    t(copied ? "deckBuilder.missing.buy.copied" : "deckBuilder.missing.buy.copy"),
                    systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.glassProminent)
            if let url = Cardmarket.wantsURL(locale: L10n.shared.current.rawValue) {
                Link(destination: url) {
                    Label(t("deckBuilder.missing.buy.openWants"), systemImage: "cart")
                }
                .buttonStyle(.glass)
            }
            ShareLink(item: text) {
                Label(t("ios.common.share"), systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
        }
        .sensoryFeedback(.success, trigger: copied)
    }

    @ViewBuilder
    private func row(_ card: DeckBuilderModel.MissingCard) -> some View {
        HStack(spacing: Spacing.s) {
            Text("\(card.missing)×")
                .font(.subheadline.bold().monospacedDigit())
                .frame(width: 34, alignment: .trailing)
            Text(card.card.name)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.s)
            if let url = app.marketURL(for: card.card) {
                Link(destination: url) {
                    Image(systemName: "cart")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("deckBuilder.missing.buy.one"))
            }
        }
    }
}
