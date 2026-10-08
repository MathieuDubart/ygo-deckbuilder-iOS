import SwiftUI
import UniformTypeIdentifiers

/// Deck builder : zones Main / Extra / Side, validation live, cartes manquantes, guide,
/// export .ydk. Toucher une carte ouvre sa fiche avec le bloc « Dans ce deck ».
struct DeckBuilderScreen: View {
    let deckId: String

    @Environment(AppState.self) private var app
    @State private var model: DeckBuilderModel?
    @State private var loadError: String?
    @State private var banlistMessage: String?

    var body: some View {
        Group {
            if let model {
                DeckBuilderContent(model: model, banlistMessage: banlistMessage)
            } else if let loadError {
                ContentUnavailableView(t("layout.pages.deckNotFound"), systemImage: "rectangle.stack.badge.minus", description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .task(id: app.collectionVersion) { await load() }
        .task {
            // La banlist change bien plus souvent que le reste du catalogue. On la relit à
            // l'ouverture, SANS faire attendre le deck : il s'affiche avec la liste connue, et
            // on ne recharge que si un statut a bougé. Le serveur borne la fréquence réelle.
            guard let status = try? await app.api.refreshBanlist(), status.changed,
                  let deck = try? await app.api.deck(deckId),
                  // Le modèle peut ne pas être encore construit : annoncer une
                  // revérification qu'on n'a pas pu appliquer ferait mentir le bandeau.
                  let model
            else { return }
            // Les cartes, pas seulement les quantités : le statut vit dans la carte.
            model.refreshCards(from: deck)
            banlistMessage = t("deckBuilder.banlist.updated")
        }
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
    /// Mot d'explication quand la banlist vient de changer sous les pieds du joueur.
    var banlistMessage: String?

    @Environment(AppState.self) private var app
    @State private var name = ""
    @State private var selected: CardLink?
    @State private var picking = false
    @State private var showingGuide = false
    @State private var pendingLink: CardLink?
    @State private var wishlistMessage: String?
    @State private var issuesMessage: String?
    @FocusState private var editingName: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                if let banlistMessage {
                    Label(banlistMessage, systemImage: "arrow.trianglehead.2.clockwise")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                IssuesView(model: model, message: $issuesMessage)
                if let issuesMessage {
                    Text(issuesMessage).font(.footnote).foregroundStyle(Theme.success)
                }
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
                Button(t("ios.deck.testInDuel"), systemImage: "bolt.shield") {
                    Task {
                        await model.flush()
                        app.testInDuel(model.deckId)
                    }
                }
                .disabled(model.entries.isEmpty)
            }
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
    @Binding var message: String?

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
                // Seules les anomalies de banlist se réparent toutes seules : une zone trop
                // petite ou un monstre mal placé demandent un choix de joueur.
                if !model.banlistFixes.isEmpty {
                    Button(t("deckBuilder.issues.fix"), systemImage: "scissors") {
                        let removed = model.applyBanlistFixes()
                        message = t("deckBuilder.issues.fixed", ["count": removed])
                    }
                    .buttonStyle(.glass)
                    .font(.footnote.weight(.medium))
                    .padding(.top, Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .strokeBorder(Theme.warning.opacity(0.35))
            }
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
        // Une interdiction n'est pas un quota : « 2 exemplaires sur 0 » ne veut rien dire
        case .forbidden: return t("deckBuilder.issues.forbidden", ["name": name, "count": count])
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
            .padding(Spacing.m)
            .overlay {
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .strokeBorder(Theme.danger.opacity(0.35))
            }
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

    /// Un exemplaire = une pochette, comme dans un classeur. Les exemplaires qu'on ne possède
    /// pas gardent leur place, en creux : on voit le deck tel qu'il sera, et ce qui manque.
    private struct Copy: Identifiable {
        let entry: DeckBuilderModel.Entry
        let index: Int
        let missing: Bool
        var id: String { "\(entry.card.id)-\(index)" }
    }

    private func copies(_ entries: [DeckBuilderModel.Entry]) -> [Copy] {
        entries.flatMap { entry in
            (0..<max(0, entry.quantity)).map { Copy(entry: entry, index: $0, missing: $0 >= entry.owned) }
        }
    }

    var body: some View {
        let entries = model.cards(in: zone)
        let cardCopies = copies(entries)
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(t("common.zones.\(zone.rawValue)")) { counter }
            if cardCopies.isEmpty {
                Text(t(zone == .side ? "deckBuilder.zone.emptySide" : "ios.deck.emptyZone"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                    .pocket(padding: 0)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: GridWidth.compactCard), spacing: Spacing.xs)],
                    spacing: Spacing.xs
                ) {
                    ForEach(cardCopies) { copy in
                        Button { onOpen(copy.entry.card.id) } label: {
                            CardArt(card: copy.entry.card, dimmed: copy.missing)
                                .overlay(alignment: .bottom) {
                                    if copy.missing {
                                        Text(t("deckBuilder.zone.missingBadge"))
                                            .codeStyle(9, weight: .bold)
                                            .foregroundStyle(Theme.danger)
                                            .padding(.bottom, 4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: copy.entry) }
                    }
                }
            }
        }
        .animation(.snappy, value: cardCopies.map(\.id))
    }

    /// Le compte, avec la fourchette autorisée en second plan : « 38/40–60 ».
    private var counter: some View {
        let range = DeckRules.range(zone)
        let count = model.count(zone)
        let short = zone == .main && count < range.lowerBound
        return HStack(spacing: 0) {
            Text("\(count)")
                .foregroundStyle(short ? Theme.warning : .secondary)
            Text(zone == .main ? "/\(range.lowerBound)–\(range.upperBound)" : "/\(range.upperBound)")
                .foregroundStyle(.tertiary)
        }
        .codeStyle(14, weight: .medium)
    }

    @ViewBuilder
    private func menu(for entry: DeckBuilderModel.Entry) -> some View {
        let zoneName = t("common.zones.\(zone.rawValue)")
        Button(t("deckBuilder.actions.addOne", ["zone": zoneName]), systemImage: "plus") {
            model.add(entry.card, to: zone)
        }
        Button(t("deckBuilder.actions.removeOne", ["zone": zoneName]), systemImage: "minus") {
            model.removeOne(entry.card.id, from: zone)
        }
        if zone != .side {
            Button(t("ios.deck.moveToSide"), systemImage: "arrow.turn.down.right") {
                if model.add(entry.card, to: .side) == nil { model.removeOne(entry.card.id, from: zone) }
            }
        }
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
