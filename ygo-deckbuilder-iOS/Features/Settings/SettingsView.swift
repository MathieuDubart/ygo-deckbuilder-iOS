import SwiftUI

/// Compte, langue, serveur, mise à jour de la meta (admin).
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var metaStatus: Loadable<SyncStatus?> = .idle
    @State private var syncing = false
    @State private var syncMessage: String?

    var body: some View {
        @Bindable var l10n = L10n.shared
        NavigationStack {
            Form {
                if let user = app.user {
                    Section(t("ios.settings.account")) {
                        LabeledContent(t("auth.fields.username"), value: user.username)
                        LabeledContent(t("auth.fields.email"), value: user.email)
                    }
                }

                Section {
                    Picker(t("common.locale.label"), selection: $l10n.preference) {
                        Text(t("ios.settings.systemLanguage")).tag(AppLocale?.none)
                        ForEach(AppLocale.allCases) { locale in
                            Text(locale.displayName).tag(AppLocale?.some(locale))
                        }
                    }
                } footer: {
                    Text(t("ios.settings.languageHint"))
                }

                if app.user != nil { MarketSection() }

                Section(t("ios.settings.server")) {
                    LabeledContent(t("ios.server.current"), value: app.server.url?.absoluteString ?? "—")
                    Button(t("ios.server.change"), role: .destructive) {
                        Task {
                            await app.forgetServer()
                            dismiss()
                        }
                    }
                }

                Section(t("ios.settings.meta")) {
                    switch metaStatus {
                    case .loaded(let status?):
                        Text(metaStatusText(status))
                            .font(.callout)
                            .foregroundStyle(status.lastStatus == "OK" ? Color.secondary : Theme.warning)
                    case .loaded(.none):
                        Text(t("suggestions.meta.empty.title"))
                            .foregroundStyle(.secondary)
                    default:
                        ProgressView()
                    }
                    if app.user?.isAdmin == true {
                        Button {
                            Task { await syncMeta() }
                        } label: {
                            HStack {
                                Text(t("suggestions.meta.status.refresh"))
                                if syncing {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(syncing)
                    }
                    if let syncMessage {
                        Text(syncMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(t("layout.logout"), role: .destructive) {
                        Task {
                            dismiss()
                            await app.signOut()
                        }
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text(t("ios.settings.credits"))
                }
            }
            .navigationTitle(t("ios.settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
                }
            }
            .task { metaStatus = await .fetch(metaStatus) { try await app.api.metaStatus() } }
            .onChange(of: l10n.current) { app.refreshAll() }
        }
    }

    private func metaStatusText(_ status: SyncStatus) -> String {
        let date = status.lastSyncAt.map(L10n.shared.date) ?? "—"
        return status.lastStatus == "OK"
            ? t("suggestions.meta.status.ok", ["date": date, "count": status.cardCount])
            : t("suggestions.meta.status.failed", ["date": date])
    }

    private func syncMeta() async {
        syncing = true
        defer { syncing = false }
        do {
            let result = try await app.api.syncMeta()
            syncMessage = t("suggestions.meta.status.synced", ["archetypes": result.archetypes, "lists": result.lists])
            metaStatus = await .fetch(metaStatus) { try await app.api.metaStatus() }
            app.collectionChanged()
        } catch {
            syncMessage = error.localizedDescription
        }
    }
}

/**
 Ce que les liens d'achat doivent montrer. Réglé une fois ici plutôt que redemandé à chaque
 clic : on achète presque toujours dans la même langue et au même état.

 Le serveur fait foi — on envoie, puis on relit l'utilisateur — et seul le champ touché part
 dans la requête, pour ne pas écraser l'autre préférence au passage.
 */
private struct MarketSection: View {
    @Environment(AppState.self) private var app
    @State private var saving = false
    @State private var failure: String?

    var body: some View {
        Section {
            Picker(
                t("social.profile.market.language"),
                selection: Binding(
                    get: { app.user?.marketLanguage },
                    set: { save(.init(marketLanguage: .some($0))) })
            ) {
                Text(t("social.profile.market.languageDefault")).tag(CardLanguage?.none)
                // Seulement celles sur lesquelles Cardmarket sait filtrer : proposer le
                // japonais donnerait un choix sans effet.
                ForEach(Cardmarket.languages) { language in
                    Text(language.rawValue).tag(CardLanguage?.some(language))
                }
            }
            Picker(
                t("social.profile.market.condition"),
                selection: Binding(
                    get: { app.user?.marketMinCondition },
                    set: { save(.init(marketMinCondition: .some($0))) })
            ) {
                Text(t("social.profile.market.conditionAny")).tag(CardCondition?.none)
                ForEach(CardCondition.allCases) { condition in
                    Text(t("cards.conditions.\(condition.rawValue)"))
                        .tag(CardCondition?.some(condition))
                }
            }
        } header: {
            Text(t("social.profile.market.title"))
        } footer: {
            // L'échec ne doit pas être muet : sinon le sélecteur revient tout seul à son
            // ancienne valeur après la relecture, sans que personne sache pourquoi.
            Text(failure ?? t("social.profile.market.hint"))
                .foregroundStyle(failure == nil ? Color.secondary : Theme.danger)
        }
        .disabled(saving)
    }

    private func save(_ body: UpdateProfileBody) {
        saving = true
        failure = nil
        Task {
            defer { saving = false }
            do {
                try await app.api.updateSettings(body)
            } catch {
                failure = error.localizedDescription
            }
            await app.refreshUser()
        }
    }
}

/// Bouton de la barre d'outils qui ouvre les réglages.
struct SettingsButton: View {
    @State private var presented = false

    var body: some View {
        Button(t("ios.settings.title"), systemImage: "person.crop.circle") { presented = true }
            .sheet(isPresented: $presented) { SettingsView() }
    }
}
