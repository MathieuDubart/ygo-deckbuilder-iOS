import SwiftUI
import UniformTypeIdentifiers

/// Deck builder : zones Main / Extra / Side, validation live, cartes manquantes, guide,
/// export .ydk. Toucher une carte ouvre sa fiche avec le bloc « Dans ce deck ».
struct DeckBuilderScreen: View {
    let deckId: String

    @Environment(AppState.self) private var app
    @State private var model: DeckBuilderModel?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let model {
                DeckBuilderContent(model: model)
            } else if let loadError {
                ContentUnavailableView(t("layout.pages.deckNotFound"), systemImage: "rectangle.stack.badge.minus", description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .task(id: app.collectionVersion) { await load() }
        .onDisappear {
            let model = model
            Task { await model?.flush() }
        }
    }

    private func load() async {
        do {
            let deck = try await app.api.deck(deckId)
            if let model {
                model.refreshOwned(from: deck)
            } else {
                let created = DeckBuilderModel(deck: deck, api: app.api)
                created.onSaved = { [weak app] in app?.decksChanged() }
                model = created
            }
        } catch {
            if model == nil { loadError = error.localizedDescription }
        }
    }
}

private struct DeckBuilderContent: View {
    @Bindable var model: DeckBuilderModel

    @Environment(AppState.self) private var app
    @State private var name = ""
    @State private var selected: CardLink?
    @State private var picking = false
    @State private var showingGuide = false
    @State private var pendingLink: CardLink?
    @State private var wishlistMessage: String?
    @FocusState private var editingName: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                IssuesView(model: model)
                MissingView(model: model, message: $wishlistMessage)
                ForEach(DeckZone.allCases) { zone in
                    ZoneSection(model: model, zone: zone) { selected = CardLink(cardId: $0) }
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.xl)
        }
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(t("deckBuilder.header.guide"), systemImage: "book.pages") { showingGuide = true }
                    .disabled(model.entries.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: YdkFile(name: model.name, text: ydk), preview: SharePreview("\(model.name).ydk")) {
                    Label(t("ios.deck.exportYdk"), systemImage: "square.and.arrow.up")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                picking = true
            } label: {
                Label(t("ios.deck.addCards"), systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.xxs)
            }
            .buttonStyle(.glassProminent)
            .padding(.bottom, Spacing.s)
        }
        .onAppear { name = model.name }
        .sheet(isPresented: $picking) { CardPickerView(model: model) }
        .sheet(isPresented: $showingGuide, onDismiss: openPending) {
            NavigationStack {
                ScrollView {
                    DeckGuideView(cards: model.guideCards, name: model.name) { id in
                        pendingLink = CardLink(cardId: id)
                        showingGuide = false
                    }
                    .padding(Spacing.l)
                }
                .navigationTitle(t("deckBuilder.header.guideDialogTitle", ["name": model.name]))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(t("common.actions.close"), systemImage: "xmark") { showingGuide = false }
                    }
                }
            }
        }
        .cardDetailSheet($selected, builder: model)
    }

    /// Une feuille ne peut s'ouvrir qu'une fois la précédente fermée.
    private func openPending() {
        if let link = pendingLink {
            pendingLink = nil
            selected = link
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            TextField(t("deckBuilder.header.nameLabel"), text: $name)
                .font(.title2.bold())
                .focused($editingName)
                .submitLabel(.done)
                .onSubmit { model.rename(name) }
                .onChange(of: editingName) { _, focused in if !focused { model.rename(name) } }

            HStack(spacing: Spacing.s) {
                Menu {
                    Picker(t("decks.new.format"), selection: Binding(get: { model.format }, set: { model.setFormat($0) })) {
                        ForEach(DeckFormat.allCases) { Text(t("decks.formats.\($0.rawValue)")).tag($0) }
                    }
                } label: {
                    Pill(text: t("decks.formats.\(model.format.rawValue)"), tint: .accentColor, systemImage: "chevron.down")
                }
                ForEach(DeckZone.allCases) { zone in
                    let count = model.count(zone)
                    Text("\(t("common.zones.\(zone.rawValue)")) \(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(zone == .main && count < 40 ? Theme.warning : .secondary)
                }
                Spacer()
                SaveStatusView(status: model.status) { model.retrySave() }
                    .font(.caption)
                    .labelStyle(.iconOnly)
            }
        }
    }

    /// .ydk généré localement (même format que l'export de l'API).
    private var ydk: String {
        func section(_ zone: DeckZone) -> [String] {
            model.cards(in: zone).flatMap { Array(repeating: String($0.card.id), count: $0.quantity) }
        }
        return (["#created by ygo-deckbuilder", "#main"] + section(.main) + ["#extra"] + section(.extra)
            + ["!side"] + section(.side) + [""]).joined(separator: "\n")
    }
}

private struct SaveStatusView: View {
    let status: DeckBuilderModel.SaveStatus
    let retry: () -> Void

    var body: some View {
        switch status {
        case .saved:
            Label(t("deckBuilder.save.saved"), systemImage: "checkmark.icloud")
                .foregroundStyle(.secondary)
        case .dirty:
            Label(t("deckBuilder.save.dirty"), systemImage: "pencil")
                .foregroundStyle(.secondary)
        case .saving:
            Label(t("deckBuilder.save.saving"), systemImage: "arrow.triangle.2.circlepath.icloud")
                .foregroundStyle(.secondary)
        case .error:
            Button(t("deckBuilder.save.error"), systemImage: "exclamationmark.icloud", action: retry)
                .foregroundStyle(Theme.danger)
        }
    }
}

private struct IssuesView: View {
    let model: DeckBuilderModel

    var body: some View {
        let issues = model.issues
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Label(t("deckBuilder.issues.title"), systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.warning)
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    Text("· \(describe(issue))").font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
            .background(Theme.warning.opacity(0.1), in: .rect(cornerRadius: Radius.s, style: .continuous))
        }
    }

    private func describe(_ issue: DeckIssue) -> String {
        let zone = issue.zone.map { t("common.zones.\($0.rawValue)") } ?? ""
        let name = issue.cardId.map(model.cardName) ?? ""
        let count = issue.count ?? 0
        let limit = issue.limit ?? 0
        switch issue.code {
        case .zoneTooSmall: return t("deckBuilder.issues.zoneTooSmall", ["zone": zone, "count": count, "limit": limit])
        case .zoneTooLarge: return t("deckBuilder.issues.zoneTooLarge", ["zone": zone, "count": count, "limit": limit])
        case .tooManyCopies: return t("deckBuilder.issues.tooManyCopies", ["name": name, "count": count, "limit": limit])
        case .wrongZone: return t("deckBuilder.issues.wrongZone", ["name": name, "zone": zone])
        }
    }
}

private struct MissingView: View {
    let model: DeckBuilderModel
    @Binding var message: String?
    @Environment(AppState.self) private var app
    @State private var adding = false

    var body: some View {
        let missing = model.missing
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(L10n.shared.rich("deckBuilder.missing.summary", [
                    "count": missing.reduce(0) { $0 + $1.missing },
                    "cost": L10n.shared.price(model.missingCost),
                ]))
                .font(.subheadline)
                Text(missing.map { "\($0.missing)× \($0.card.name)" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Button {
                    Task { await addAll(missing) }
                } label: {
                    Label(t("deckBuilder.missing.addAll"), systemImage: "heart")
                }
                .buttonStyle(.glass)
                .disabled(adding)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(Theme.success)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tileSurface()
        }
    }

    private func addAll(_ missing: [DeckBuilderModel.MissingCard]) async {
        adding = true
        defer { adding = false }
        let api = app.api
        let deckId = model.deckId
        await withTaskGroup(of: Void.self) { group in
            for m in missing {
                let body = AddWishlistBody(cardId: m.card.id, deckId: deckId, quantity: min(m.missing, 3))
                group.addTask { try? await api.addToWishlist(body) }
            }
        }
        message = t("deckBuilder.missing.added", ["count": missing.count])
        app.wishlistChanged()
    }
}

private struct ZoneSection: View {
    let model: DeckBuilderModel
    let zone: DeckZone
    let onOpen: (Int) -> Void

    var body: some View {
        let entries = model.cards(in: zone)
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(t("common.zones.\(zone.rawValue)")) {
                let range = DeckRules.range(zone)
                Text("\(model.count(zone))/\(zone == .main ? range.lowerBound : range.upperBound)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(zone == .main && model.count(zone) < range.lowerBound ? Theme.warning : .secondary)
            }
            if entries.isEmpty {
                Text(t(zone == .side ? "deckBuilder.zone.emptySide" : "ios.deck.emptyZone"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: GridWidth.compactCard), spacing: Spacing.s)], spacing: Spacing.m) {
                    ForEach(entries) { entry in
                        Button { onOpen(entry.card.id) } label: {
                            CardTile(
                                card: entry.card, quantity: entry.quantity,
                                missing: max(0, entry.quantity - entry.owned))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(t("deckBuilder.actions.addOne", ["zone": t("common.zones.\(zone.rawValue)")]), systemImage: "plus") {
                                model.add(entry.card, to: zone)
                            }
                            Button(t("deckBuilder.actions.removeOne", ["zone": t("common.zones.\(zone.rawValue)")]), systemImage: "minus") {
                                model.removeOne(entry.card.id, from: zone)
                            }
                            if zone != .side {
                                Button(t("ios.deck.moveToSide"), systemImage: "arrow.turn.down.right") {
                                    if model.add(entry.card, to: .side) == nil { model.removeOne(entry.card.id, from: zone) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .animation(.snappy, value: entries.map(\.id))
    }
}

/// Fichier .ydk partagé (AirDrop, Fichiers, messagerie…).
nonisolated struct YdkFile: Transferable, Sendable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .ydk) { file in
            let safe = file.name.replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory.appending(path: "\(safe).ydk")
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

extension UTType {
    /// .ydk (YGOPro / EDOPro / Master Duel) : du texte.
    nonisolated static var ydk: UTType { UTType(filenameExtension: "ydk", conformingTo: .plainText) ?? .plainText }
}
