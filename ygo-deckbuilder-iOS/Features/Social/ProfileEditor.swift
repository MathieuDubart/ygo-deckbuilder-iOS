import PhotosUI
import SwiftUI

/// Pseudo, photo de profil et bannière. Trois réglages, donc une feuille et pas un écran.
struct ProfileEditor: View {
    let user: PublicProfile

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var busy = false
    @State private var error: String?

    /// Règle du serveur, répétée pour ne pas envoyer une requête qu'on sait refusée.
    private var valid: Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard (3...20).contains(trimmed.count), let first = trimmed.first, first.isLetter || first.isNumber
        else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
    }

    private var changed: Bool { username.trimmingCharacters(in: .whitespaces) != user.username }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(t("social.profile.username"), text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(t("social.profile.save")) { Task { await rename() } }
                        .disabled(!changed || !valid || busy)
                } header: {
                    Text(t("social.profile.username"))
                } footer: {
                    Text(t("social.profile.usernameHint"))
                }

                Section {
                    ImageRow(kind: "avatar", label: t("social.profile.avatar"), current: user.avatarUrl, circular: true)
                    ImageRow(kind: "banner", label: t("social.profile.banner"), current: user.bannerUrl, circular: false)
                } footer: {
                    Text(t("social.profile.imageHint"))
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(t("social.profile.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
                }
            }
        }
        .onAppear { username = user.username }
    }

    private func rename() async {
        busy = true
        defer { busy = false }
        do {
            try await app.api.updateUsername(username.trimmingCharacters(in: .whitespaces))
            app.socialChanged()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Une image de profil : aperçu, envoi depuis la photothèque, retrait.
private struct ImageRow: View {
    let kind: String
    let label: String
    let current: String?
    let circular: Bool

    @Environment(AppState.self) private var app
    @State private var picked: PhotosPickerItem?
    @State private var busy = false
    @State private var error: String?
    /// Chemin renvoyé par le dernier envoi : il porte un jeton aléatoire, donc l'aperçu
    /// change sans dépendre du rechargement du profil ni des caches d'images.
    @State private var uploaded: String?

    /// L'image à considérer : celle qu'on vient d'envoyer, sinon celle du profil chargé.
    private var shown: String? { uploaded ?? current }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                preview
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(label).font(.subheadline)
                    HStack(spacing: Spacing.m) {
                        PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                            Text(shown == nil ? t("social.profile.upload") : t("social.profile.replace"))
                                .font(.caption)
                        }
                        .disabled(busy)
                        if shown != nil {
                            Button(t("social.profile.remove"), role: .destructive) {
                                Task { await remove() }
                            }
                            .font(.caption)
                            .disabled(busy)
                        }
                    }
                }
                Spacer(minLength: 0)
                if busy { ProgressView() }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(Theme.danger)
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    @ViewBuilder
    private var preview: some View {
        let url = app.api.absoluteURL(shown)
        RemoteImage([url], width: .thumb, optimized: false) {
            Rectangle().fill(.fill.tertiary)
        }
        .frame(width: circular ? 48 : 96, height: 48)
        .clipShape(circular ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: Radius.s)))
    }

    private func upload(_ item: PhotosPickerItem) async {
        busy = true
        defer {
            busy = false
            // Remettre à zéro : rechoisir la même photo doit relancer un envoi.
            picked = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            error = t("ios.errors.imageUnreadable")
            return
        }
        do {
            // Le type réel importe peu : le serveur réencode tout en WebP et refuse ce qu'il
            // ne sait pas décoder. On annonce le plus courant.
            uploaded = try await app.api.uploadProfileImage(kind, data: data, mimeType: "image/jpeg").url
            app.socialChanged()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        busy = true
        defer { busy = false }
        guard (try? await app.api.removeProfileImage(kind)) != nil else { return }
        uploaded = nil
        app.socialChanged()
    }
}

/**
 Choix des cartes mises en avant, dans sa propre collection. On envoie la liste entière :
 réordonner est alors la même opération qu'ajouter, et l'ordre affiché est celui qu'on a
 touché.
 */
struct ShowcasePicker: View {
    /// Les cartes déjà mises en avant, avec leur visuel : sans elles, celles qui ne sont pas
    /// dans la première page de la collection seraient impossibles à retirer, et la sélection
    /// resterait bloquée à son maximum.
    let selected: [ProfileCard]

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var picked: [String] = []
    @State private var query = ""
    @State private var items: Loadable<[CollectionItem]> = .idle
    @State private var busy = false
    @State private var error: String?
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text(t("social.profile.showcase.dialogHint", ["max": maxProfileCards]))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Pill(
                        text: t("social.profile.showcase.selected", [
                            "count": picked.count, "max": maxProfileCards,
                        ]),
                        tint: picked.count >= maxProfileCards ? Theme.warning : .secondary)

                    if !selected.isEmpty {
                        Text(t("social.profile.showcase.title"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: GridWidth.card), spacing: Spacing.s)],
                            spacing: Spacing.m
                        ) {
                            ForEach(selected) { card in
                                tile(card.card, printId: card.printId, code: card.printCode)
                            }
                        }
                        Divider()
                    }

                    LoadableView(state: items, retry: load) { list in
                        if list.isEmpty {
                            Text(t("social.profile.showcase.noResults"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        } else {
                            grid(list)
                        }
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.section)
            }
            .navigationTitle(t("social.profile.showcase.dialogTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: t("social.profile.showcase.search"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.actions.cancel"), systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("social.profile.showcase.done"), systemImage: "checkmark") {
                        Task { await save() }
                    }
                    .disabled(busy)
                }
            }
            .task(id: query) {
                let isTyping = query != typed
                typed = query
                if isTyping {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                }
                await load()
            }
            .onAppear { picked = selected.map(\.printId) }
            .overlay(alignment: .bottom) {
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                        .padding()
                }
            }
        }
    }

    private func grid(_ list: [CollectionItem]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: GridWidth.card), spacing: Spacing.s)],
            spacing: Spacing.m
        ) {
            // Une ligne sans impression ne peut pas être mise en avant : le profil montre une
            // édition précise, pas « la carte, quelque part ». Celles déjà choisies sont
            // montrées plus haut, on ne les répète pas.
            ForEach(list.filter { item in
                guard let print = item.print else { return false }
                return !selected.contains { $0.printId == print.id }
            }) { item in
                tile(item.card, printId: item.print?.id ?? "", code: item.print?.printCode ?? "")
            }
        }
    }

    /// Une vignette sélectionnable, avec son rang quand elle est retenue.
    private func tile(_ card: CardSummary, printId: String, code: String) -> some View {
        let position = picked.firstIndex(of: printId)
        return Button { toggle(printId) } label: {
            VStack(alignment: .leading, spacing: 3) {
                CardArt(card: card)
                    .overlay(alignment: .topTrailing) {
                        if let position {
                            Pill(text: "\(position + 1)", tint: .accentColor).padding(3)
                        }
                    }
                    .overlay {
                        if position != nil {
                            RoundedRectangle(cornerRadius: Radius.s)
                                .stroke(Color.accentColor, lineWidth: 2)
                        }
                    }
                Text(code)
                    .font(.system(size: 9, weight: .medium).monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ printId: String) {
        if let index = picked.firstIndex(of: printId) {
            picked.remove(at: index)
        } else if picked.count < maxProfileCards {
            picked.append(printId)
        }
    }

    private func load() async {
        var request = CollectionQuery()
        request.q = query
        request.pageSize = 60
        items = await .fetch(items) { try await app.api.collection(request).items }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await app.api.setProfileCards(picked)
            app.socialChanged()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
