import SwiftUI

/**
 La langue dans laquelle on range sa collection, et le moyen d'y ramener ce qui n'y est pas.

 L'écran ne s'ouvre pas sur un bouton « normaliser » mais sur la répartition réelle, parce que
 la question n'a de sens qu'avec les nombres sous les yeux — et parce que ramener quatre cents
 cartes dans une langue ne se défait pas. Ce qui va fusionner est annoncé en toutes lettres :
 c'est la seule partie inquiétante de l'opération.
 */
struct CollectionLanguageView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var state: Loadable<CollectionLanguageState> = .idle
    /// Langue envisagée. Nil tant qu'on n'a rien touché : c'est celle du serveur qui parle.
    @State private var target: CardLanguage?
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            LoadableView(state: state, retry: load) { value in
                List {
                    Section {
                        Picker(t("collection.language.label"), selection: chosenBinding(value)) {
                            ForEach(CardLanguage.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } footer: {
                        if value.language == nil { Text(t("collection.language.neverChosen")) }
                    }

                    if value.report.byLanguage.count > 1 { distribution(value) }
                    actions(value)

                    if let message {
                        Section { Text(message).font(.footnote).foregroundStyle(Theme.success) }
                    }
                }
            }
            .navigationTitle(t("collection.language.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.actions.close"), systemImage: "checkmark") { dismiss() }
                }
            }
        }
        // L'aperçu dépend de la langue envisagée : on le redemande quand elle change.
        .task(id: target) { await load() }
    }

    @ViewBuilder
    private func distribution(_ value: CollectionLanguageState) -> some View {
        let total = max(1, value.report.copies)
        Section(t("collection.language.breakdown")) {
            ForEach(value.report.byLanguage) { row in
                HStack(spacing: Spacing.m) {
                    Text(row.language.rawValue)
                        .codeStyle(11, weight: row.language == value.report.target ? .bold : .regular)
                        .frame(width: 26, alignment: .leading)
                    Meter(value: row.copies, total: total)
                    Text(t("collection.language.copies", ["count": row.copies, "piles": row.piles]))
                        .codeStyle(11)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ value: CollectionLanguageState) -> some View {
        // La langue DU RAPPORT, pas celle du sélecteur : pendant le rechargement les deux
        // divergent, et annoncer « tout passer en EN (12) » avec un 12 calculé pour FR est
        // pire que d'attendre une seconde.
        let language = value.report.target
        // Tant que le rapport affiché ne correspond pas au sélecteur — rechargement en cours,
        // ou requête échouée qui a laissé l'ancien rapport — agir ferait l'inverse de ce qui
        // est écrit. Sur une opération qui ne se défait pas, on préfère un bouton inerte.
        let stale = chosen(value) != value.report.target
        Section {
            if value.report.affected > 0 {
                Button {
                    Task { await apply(language, normalize: true) }
                } label: {
                    Label(
                        t(
                            "collection.language.normalize",
                            ["language": language.rawValue, "count": value.report.affected]),
                        systemImage: "character.book.closed")
                }
                .disabled(busy || stale)
            }
            // Hors du test ci-dessus : une collection vide ou déjà uniforme n'a rien à
            // normaliser, mais doit quand même pouvoir enregistrer sa langue de rangement.
            if value.language != language {
                Button(t("collection.language.onlyFuture")) {
                    Task { await apply(language, normalize: false) }
                }
                .disabled(busy || stale)
            }
        } footer: {
            if value.report.affected == 0 {
                Text(t("collection.language.alreadyUniform", ["language": language.rawValue]))
            } else if value.report.merged > 0 {
                Text(t("collection.language.willMerge", ["count": value.report.merged]))
            } else {
                Text(t("collection.language.willRetag", ["count": value.report.affected]))
            }
        }
    }

    private func chosen(_ value: CollectionLanguageState) -> CardLanguage {
        target ?? value.effective
    }

    private func chosenBinding(_ value: CollectionLanguageState) -> Binding<CardLanguage> {
        // Le message de confirmation porte sur ce qu'on vient de faire : il s'efface quand on
        // envisage autre chose, pas au rechargement qui suit l'action elle-même.
        Binding(get: { chosen(value) }, set: { target = $0; message = nil })
    }

    private func load() async {
        state = await .fetch(state) { try await app.api.collectionLanguage(target: target) }
    }

    private func apply(_ language: CardLanguage, normalize: Bool) async {
        busy = true
        defer { busy = false }
        guard let result = try? await app.api.setCollectionLanguage(
            CollectionLanguageBody(language: language, normalize: normalize))
        else { return }
        message =
            result.retagged > 0 || result.merged > 0
            ? t(
                "collection.language.done",
                ["count": result.retagged, "merged": result.merged])
            : t("collection.language.saved", ["language": language.rawValue])
        // Le réglage vit sur l'utilisateur, et la normalisation a déplacé des exemplaires.
        await app.refreshUser()
        app.collectionChanged()
        await load()
    }
}
