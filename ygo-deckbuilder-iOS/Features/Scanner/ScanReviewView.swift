import SwiftUI

/// Relecture de la file scannée : on vérifie chaque carte, on corrige l'édition, la quantité
/// ou la langue, on en ajoute à la main, puis on valide le tout d'un coup.
struct ScanReviewView: View {
    let batch: ScanBatch
    /// Appelé quand tout est passé : le scanner se ferme.
    var onDone: () -> Void

    @Environment(AppState.self) private var app
    @State private var adding = false
    @State private var commitFailures = 0

    var body: some View {
        List {
            ForEach(batch.drafts) { draft in
                NavigationLink {
                    ScanDraftEditor(draft: draft)
                } label: {
                    row(draft)
                }
            }
            .onDelete { batch.remove(atOffsets: $0) }

            if !batch.failures.isEmpty {
                Section(t("ios.scan.review.failures")) {
                    ForEach(batch.failures, id: \.self) { failure in
                        Text(failure).font(.footnote).foregroundStyle(Theme.danger)
                    }
                }
            }
        }
        .overlay {
            if batch.isEmpty {
                ContentUnavailableView(
                    t("ios.scan.review.empty"), systemImage: "tray",
                    description: Text(t("ios.scan.review.emptyHint")))
            }
        }
        .navigationTitle(t("ios.scan.review.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(t("ios.scan.review.addManually"), systemImage: "plus") { adding = true }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !batch.isEmpty { commitBar }
        }
        .sheet(isPresented: $adding) { ScanManualAddView(batch: batch) }
        .sensoryFeedback(.error, trigger: commitFailures)
    }

    private func row(_ draft: ScanDraft) -> some View {
        CardRow(card: draft.card, subtitle: draft.subtitle) {
            Text("×\(draft.quantity)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var commitBar: some View {
        VStack(spacing: Spacing.s) {
            if batch.saving {
                ProgressView(value: Double(batch.saved), total: Double(max(batch.drafts.count, 1)))
            }
            Button {
                Task {
                    let ok = await batch.commit(api: app.api)
                    if batch.saved > 0 { app.collectionChanged() }
                    if ok { onDone() } else { commitFailures += 1 }
                }
            } label: {
                Label(
                    t("ios.scan.review.commit", ["count": batch.totalCopies]),
                    systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(batch.saving)
        }
        .padding(Spacing.l)
        .background(.bar)
    }
}

/// Édition d'une ligne de la file : édition, quantité, état, langue, 1re édition.
private struct ScanDraftEditor: View {
    @Bindable var draft: ScanDraft

    var body: some View {
        Form {
            Section {
                HStack(spacing: Spacing.m) {
                    CardArt(card: draft.card, width: .thumb)
                        .frame(width: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.card.name).font(.headline).lineLimit(3)
                        if let code = draft.code {
                            Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                if draft.prints.isEmpty {
                    Text(t("ios.scan.review.noPrints"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    PrintPicker(prints: draft.prints, selection: $draft.printId)
                }
                Stepper(value: $draft.quantity, in: 1...99) {
                    LabeledContent(t("cards.collectionForm.quantity"), value: "\(draft.quantity)")
                }
                Picker(t("cards.collectionForm.condition"), selection: $draft.condition) {
                    ForEach(CardCondition.allCases) { Text(t("cards.conditions.\($0.rawValue)")).tag($0) }
                }
                Picker(t("cards.collectionForm.language"), selection: $draft.language) {
                    ForEach(CardLanguage.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle(t("cards.collectionForm.firstEdition"), isOn: $draft.firstEdition)
            }
        }
        .navigationTitle(draft.card.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Ajout d'une carte à la main dans la file (carte sans code lisible, carte oubliée…).
private struct ScanManualAddView: View {
    let batch: ScanBatch

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: CardSearchModel?
    @State private var busy: Int?
    @State private var added = 0

    var body: some View {
        NavigationStack {
            List {
                if let model {
                    ForEach(model.items) { card in
                        Button {
                            Task { await pick(card) }
                        } label: {
                            CardRow(card: card) {
                                if busy == card.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(busy != nil)
                    }
                    if model.items.isEmpty && !model.loading {
                        ContentUnavailableView.search(text: model.query.q)
                    }
                }
            }
            .overlay { if model?.loading == true { ProgressView() } }
            .searchable(text: searchText, prompt: Text(t("ios.scan.review.search")))
            .navigationTitle(t("ios.scan.review.addManually"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.actions.close"), systemImage: "checkmark") { dismiss() }
                }
            }
            .task {
                guard model == nil else { return }
                let created = CardSearchModel(api: app.api)
                model = created
                await created.reload()
            }
        }
        .sensoryFeedback(.success, trigger: added)
    }

    /// Texte de recherche du modèle, sans état dupliqué côté vue.
    private var searchText: Binding<String> {
        Binding(get: { model?.query.q ?? "" }, set: { model?.query.q = $0 })
    }

    private func pick(_ card: CardSummary) async {
        busy = card.id
        defer { busy = nil }
        let detail = try? await app.api.card(card.id)
        batch.add(card: detail?.summary ?? card, prints: detail?.prints ?? [])
        added += 1
    }
}
