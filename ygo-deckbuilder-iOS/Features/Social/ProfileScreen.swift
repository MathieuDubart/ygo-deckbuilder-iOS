import SwiftUI

struct ProfileRoute: Hashable { let username: String }

/// Un profil, le sien ou celui d'un ami. Le serveur décide de ce qui est visible : l'écran
/// n'a qu'à traiter les deux formes que renvoie `ProfileView`.
struct ProfileScreen: View {
    /// nil = son propre profil.
    var username: String?
    var embedded = false

    @Environment(AppState.self) private var app
    @State private var state: Loadable<ProfileView> = .idle
    @State private var editing = false
    @State private var picking = false
    /// Carte de la vitrine ouverte en plein écran (l'objet 3D, pas la fiche).
    @State private var shown: ProfileCard?

    var body: some View {
        ScrollView {
            LoadableView(state: state, retry: load) { view in
                switch view {
                case .visible(let profile):
                    VisibleProfile(
                        profile: profile, editing: $editing, picking: $picking, shown: $shown)
                case .hidden(let user, let friendship, let requestId):
                    HiddenProfile(user: user, state: friendship, requestId: requestId)
                }
            }
        }
        .navigationTitle(state.value?.user.username ?? t("social.profile.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: Reload(username: username, social: app.socialVersion, collection: app.collectionVersion)) {
            await load()
        }
        .refreshable { await load() }
        // Une vitrine, ça se regarde : on ouvre la carte en grand, dans la rareté qu'il
        // possède, plutôt que la fiche. Une seule rareté dans la liste, donc pas de
        // sélecteur : c'est SA carte qu'on regarde.
        .fullScreenCover(item: $shown) { card in
            CardShowcaseView(card: card.card, rarities: [card.rarity], initialRarity: card.rarity)
        }
        .sheet(isPresented: $editing) {
            if case .visible(let profile) = state.value { ProfileEditor(user: profile.user) }
        }
        .sheet(isPresented: $picking) {
            if case .visible(let profile) = state.value {
                ShowcasePicker(selected: profile.cards)
            }
        }
    }

    /// Le profil dépend aussi de la collection : les repères affichés en viennent.
    private struct Reload: Equatable {
        let username: String?
        let social: Int
        let collection: Int
    }

    private func load() async {
        state = await .fetch(state) {
            if let username { try await app.api.profile(of: username) } else { try await app.api.myProfile() }
        }
    }
}

// MARK: - Profil visible

private struct VisibleProfile: View {
    let profile: Profile
    @Binding var editing: Bool
    @Binding var picking: Bool
    @Binding var shown: ProfileCard?

    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            header
            stats
            showcase
        }
        .padding(.bottom, Spacing.section)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            // La bannière déborde des marges : c'est une image de pleine largeur.
            RemoteImage([app.api.absoluteURL(profile.user.bannerUrl)], width: .large, optimized: false) {
                LinearGradient(
                    colors: [.accentColor.opacity(0.35), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                    .background(.fill.tertiary)
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                AvatarView(user: profile.user, size: 76)
                    .overlay(Circle().stroke(.background, lineWidth: 4))
                    // Moitié basse hors de la bannière : il faut donc la poser en surcouche
                    // avec un décalage, pas à l'intérieur du cadre rogné.
                    .offset(x: Spacing.l, y: 38)
            }
            .padding(.bottom, 42)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(profile.user.username).font(.title2.weight(.semibold))
                Text(
                    profile.friendsSince.map { t("social.profile.friendsSince", ["date": L10n.shared.date($0)]) }
                        ?? t("social.profile.memberSince", ["date": L10n.shared.date(profile.memberSince)])
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.l)

            HStack(spacing: Spacing.s) {
                if profile.isSelf {
                    Button(t("social.profile.edit"), systemImage: "pencil") { editing = true }
                        .buttonStyle(.bordered)
                    NavigationLink(value: MoreRoute.friends) {
                        Label(
                            t("social.profile.friendCount", ["count": profile.friendCount]),
                            systemImage: "person.2")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Pill(
                        text: t("social.profile.friendCount", ["count": profile.friendCount]),
                        tint: Theme.success)
                    Spacer(minLength: 0)
                    RemoveFriendButton(user: profile.user)
                }
            }
            .padding(.horizontal, Spacing.l)
        }
    }

    private var stats: some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                StatTile(
                    label: t("social.profile.stats.distinctCards"),
                    value: L10n.shared.number(profile.stats.distinctCards))
                StatTile(
                    label: t("social.profile.stats.copies"), value: L10n.shared.number(profile.stats.copies))
            }
            HStack(spacing: Spacing.s) {
                StatTile(label: t("social.profile.stats.sets"), value: L10n.shared.number(profile.stats.sets))
                StatTile(
                    label: t("social.profile.stats.completedSets"),
                    value: L10n.shared.number(profile.stats.completedSets), tint: Theme.success)
            }
        }
        .padding(.horizontal, Spacing.l)
    }

    @ViewBuilder
    private var showcase: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text(t("social.profile.showcase.title"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                if profile.isSelf {
                    Button(t("social.profile.showcase.choose"), systemImage: "sparkles") { picking = true }
                        .font(.caption)
                }
            }

            if profile.cards.isEmpty {
                ContentUnavailableView(
                    profile.isSelf
                        ? t("social.profile.showcase.empty")
                        : t("social.profile.showcase.emptyOther", ["username": profile.user.username]),
                    systemImage: "sparkles",
                    description: profile.isSelf ? Text(t("social.profile.showcase.emptyHint")) : nil)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: GridWidth.card), spacing: Spacing.s)],
                    spacing: Spacing.m
                ) {
                    ForEach(profile.cards) { card in
                        Button { shown = card } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                CardArt(card: card.card)
                                Text(card.printCode)
                                    .font(.system(size: 9, weight: .medium).monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                Text(card.rarity)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.l)
    }
}

// MARK: - Profil fermé

/// Un compte qui n'est pas ami : de quoi l'ajouter, et rien d'autre.
private struct HiddenProfile: View {
    let user: PublicProfile
    let state: FriendshipState
    let requestId: String?

    @Environment(AppState.self) private var app
    @State private var busy = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            AvatarView(user: user, size: 96)
            Text(user.username).font(.title3.weight(.semibold))

            VStack(spacing: Spacing.m) {
                Image(systemName: "lock")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(t("social.profile.hidden.title")).font(.subheadline.weight(.medium))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                action
            }
            .frame(maxWidth: .infinity)
            .tileSurface()
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.xl)
    }

    private var message: String {
        switch state {
        case .requestSent: t("social.profile.hidden.sent")
        case .requestReceived: t("social.profile.hidden.received", ["username": user.username])
        default: t("social.profile.hidden.description", ["username": user.username])
        }
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .none:
            Button(t("social.friends.actions.add"), systemImage: "person.badge.plus") {
                Task {
                    busy = true
                    defer { busy = false }
                    _ = try? await app.api.requestFriend(username: user.username)
                    app.socialChanged()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
        case .requestReceived:
            if let requestId {
                Button(t("social.friends.requests.accept"), systemImage: "checkmark") {
                    Task {
                        try? await app.api.respondToRequest(requestId, accept: true)
                        app.socialChanged()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .requestSent:
            Button(t("social.friends.requests.cancel"), systemImage: "xmark", role: .destructive) {
                Task {
                    try? await app.api.removeFriend(user.id)
                    app.socialChanged()
                }
            }
            .buttonStyle(.bordered)
        default:
            EmptyView()
        }
    }
}

/// Retirer un ami, avec confirmation : on y perd l'accès à son profil.
private struct RemoveFriendButton: View {
    let user: PublicProfile
    @Environment(AppState.self) private var app
    @State private var confirming = false

    var body: some View {
        Button(t("social.friends.actions.remove"), systemImage: "person.badge.minus", role: .destructive) {
            confirming = true
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .confirmationDialog(
            t("social.friends.actions.confirmRemove", ["username": user.username]),
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button(t("social.friends.actions.remove"), role: .destructive) {
                Task {
                    guard (try? await app.api.removeFriend(user.id)) != nil else { return }
                    app.socialChanged()
                }
            }
        }
    }
}
