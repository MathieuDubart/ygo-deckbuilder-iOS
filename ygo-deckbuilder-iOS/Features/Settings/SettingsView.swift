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

/// Bouton de la barre d'outils qui ouvre les réglages.
struct SettingsButton: View {
    @State private var presented = false

    var body: some View {
        Button(t("ios.settings.title"), systemImage: "person.crop.circle") { presented = true }
            .sheet(isPresented: $presented) { SettingsView() }
    }
}
