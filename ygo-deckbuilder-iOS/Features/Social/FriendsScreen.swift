import SwiftUI

/// Amis : chercher quelqu'un, répondre aux demandes, voir sa liste. Les trois tiennent dans
/// une seule liste parce qu'on y vient pour une de ces trois choses, jamais longtemps.
struct FriendsScreen: View {
    var embedded = false

    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var results: [UserSearchResult] = []
    @State private var requests: [FriendRequest] = []
    @State private var friends: Loadable<[Friend]> = .idle
    @State private var searching = false
    @State private var error: String?
    /// Dernier texte vu par la tâche de recherche : le délai ne vaut que pour la frappe.
    @State private var typed = ""

    private var incoming: [FriendRequest] { requests.filter { $0.direction == .incoming } }
    private var outgoing: [FriendRequest] { requests.filter { $0.direction == .outgoing } }

    var body: some View {
        content
            .navigationTitle(t("social.friends.title"))
            .navigationBarTitleDisplayMode(embedded ? .inline : .large)
            .searchable(text: $query, prompt: t("social.friends.search.placeholder"))
            .task(id: Reload(query: query, version: app.socialVersion)) {
                let isTyping = query != typed
                typed = query
                if isTyping {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                }
                await search()
            }
            .task(id: app.socialVersion) { await load() }
            .refreshable { await load() }
    }

    private struct Reload: Equatable {
        let query: String
        let version: Int
    }

    @ViewBuilder
    private var content: some View {
        List {
            if let error {
                Text(error).font(.footnote).foregroundStyle(Theme.danger)
            }

            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    if query.trimmingCharacters(in: .whitespaces).count < 2 {
                        Text(t("social.friends.search.hint"))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if searching && results.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if results.isEmpty {
                        Text(t("social.friends.search.noResults", [
                            "q": query.trimmingCharacters(in: .whitespaces)
                        ]))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(results) { result in
                        SearchRow(result: result)
                    }
                } header: {
                    Text(t("social.friends.search.label"))
                }
            }

            if !incoming.isEmpty {
                Section(t("social.friends.requests.incoming")) {
                    ForEach(incoming) { request in RequestRow(request: request) }
                }
            }
            if !outgoing.isEmpty {
                Section(t("social.friends.requests.outgoing")) {
                    ForEach(outgoing) { request in RequestRow(request: request) }
                }
            }

            Section(t("social.friends.list.title")) {
                LoadableView(state: friends, retry: load) { list in
                    if list.isEmpty {
                        ContentUnavailableView(
                            t("social.friends.list.empty"), systemImage: "person.2",
                            description: Text(t("social.friends.list.emptyDescription")))
                    } else {
                        ForEach(list) { friend in FriendRow(friend: friend) }
                    }
                }
            }
        }
    }

    private func load() async {
        friends = await .fetch(friends) { try await app.api.friends() }
        requests = (try? await app.api.friendRequests()) ?? requests
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            return
        }
        searching = true
        defer { searching = false }
        do {
            results = try await app.api.searchUsers(text)
            error = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
            // Frappe suivante : la requête en vol est annulée, ce n'est pas une erreur
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Lignes

private struct SearchRow: View {
    let result: UserSearchResult
    @Environment(AppState.self) private var app
    @State private var busy = false

    var body: some View {
        // Le bouton est FRÈRE du lien, pas dans son libellé : à l'intérieur, c'est la
        // cellule qui capterait l'appui et la navigation partirait à sa place.
        HStack {
            NavigationLink(value: ProfileRoute(username: result.username)) {
                // Le lien ne prend que la largeur de son libellé : sans ça, la moitié de la
                // ligne devient une zone morte et le chevron flotte au milieu.
                UserRow(user: result.user)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            action
        }
    }

    @ViewBuilder
    private var action: some View {
        switch result.state {
        case .none:
            // Un bouton dans une ligne de navigation doit porter son propre style, sinon
            // c'est toute la ligne qui réagit à l'appui.
            Button(t("social.friends.actions.add"), systemImage: "person.badge.plus") {
                Task { await add() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .disabled(busy)
        case .requestSent:
            Pill(text: t("social.friends.state.REQUEST_SENT"))
        case .requestReceived:
            if let id = result.requestId { AcceptButton(requestId: id) }
        case .friends:
            Pill(text: t("social.friends.state.FRIENDS"), tint: Theme.success)
        case .`self`:
            EmptyView()
        }
    }

    private func add() async {
        busy = true
        defer { busy = false }
        _ = try? await app.api.requestFriend(username: result.username)
        app.socialChanged()
    }
}

private struct RequestRow: View {
    let request: FriendRequest
    @Environment(AppState.self) private var app

    var body: some View {
        HStack {
            NavigationLink(value: ProfileRoute(username: request.user.username)) {
                UserRow(user: request.user)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            if request.direction == .incoming {
                AcceptButton(requestId: request.id)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(
                request.direction == .incoming
                    ? t("social.friends.requests.decline") : t("social.friends.requests.cancel"),
                systemImage: "xmark", role: .destructive
            ) {
                Task {
                    if request.direction == .incoming {
                        try? await app.api.respondToRequest(request.id, accept: false)
                    } else {
                        try? await app.api.removeFriend(request.user.id)
                    }
                    app.socialChanged()
                }
            }
        }
    }
}

private struct AcceptButton: View {
    let requestId: String
    @Environment(AppState.self) private var app
    @State private var busy = false

    var body: some View {
        Button(t("social.friends.requests.accept"), systemImage: "checkmark") {
            Task {
                busy = true
                defer { busy = false }
                try? await app.api.respondToRequest(requestId, accept: true)
                app.socialChanged()
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .disabled(busy)
    }
}

private struct FriendRow: View {
    let friend: Friend
    @Environment(AppState.self) private var app
    @State private var confirming = false

    var body: some View {
        NavigationLink(value: ProfileRoute(username: friend.username)) {
            HStack {
                UserRow(
                    user: friend.user,
                    subtitle: t("ios.social.friendCounters", [
                        "cards": friend.stats.distinctCards,
                        "sets": friend.stats.completedSets,
                    ]))
                Spacer(minLength: 0)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(t("social.friends.actions.remove"), systemImage: "person.badge.minus", role: .destructive) {
                confirming = true
            }
        }
        .confirmationDialog(
            t("social.friends.actions.confirmRemove", ["username": friend.username]),
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button(t("social.friends.actions.remove"), role: .destructive) {
                Task {
                    guard (try? await app.api.removeFriend(friend.id)) != nil else { return }
                    app.socialChanged()
                }
            }
        }
    }
}
