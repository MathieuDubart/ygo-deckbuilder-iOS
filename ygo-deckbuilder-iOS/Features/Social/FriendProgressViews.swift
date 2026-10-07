import SwiftUI

/// Comparaison compacte, sur une ligne d'extension : quelques avatars et un pourcentage.
/// Muette quand aucun ami n'a commencé — une mention « aucun ami » répétée sur trente lignes
/// ne dit rien.
struct FriendProgressStrip: View {
    let friends: [FriendSetProgress]?
    let anyEdition: Bool

    var body: some View {
        if let friends, !friends.isEmpty {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "person.2")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                ForEach(friends.prefix(3)) { row in
                    HStack(spacing: 2) {
                        AvatarView(user: row.user, size: 14)
                        Text(L10n.shared.percent(row.ratio(anyEdition: anyEdition)))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if friends.count > 3 {
                    Text("+\(friends.count - 3)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(t("social.releases.friends"))
        }
    }
}

/// Comparaison détaillée, dans la fiche d'une extension : une jauge par ami.
struct FriendProgressPanel: View {
    let friends: [FriendSetProgress]
    let anyEdition: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(t("social.releases.onThisSet"))
                .font(.subheadline.weight(.medium))
            if friends.isEmpty {
                Text(t("social.releases.nobodyStarted"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(friends) { row in
                    let owned = row.owned(anyEdition: anyEdition)
                    let total = row.total(anyEdition: anyEdition)
                    NavigationLink(value: ProfileRoute(username: row.user.username)) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack {
                                AvatarView(user: row.user, size: 20)
                                Text(row.user.username).font(.caption.weight(.medium))
                                Spacer()
                                Text("\(owned)/\(total) · \(L10n.shared.percent(row.ratio(anyEdition: anyEdition)))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Meter(value: owned, total: total, height: 4)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Qui, parmi les amis, possède cette impression : pastilles pleines pour l'impression
/// exacte, estompées et cerclées pour une autre édition — la même distinction que ses
/// propres badges.
struct PrintOwners: View {
    let owners: [String]?
    let elsewhere: [String]?
    let byId: [String: PublicProfile]

    private var exact: [PublicProfile] { (owners ?? []).compactMap { byId[$0] } }
    private var other: [PublicProfile] { (elsewhere ?? []).compactMap { byId[$0] } }

    var body: some View {
        if !exact.isEmpty || !other.isEmpty {
            HStack(spacing: 1) {
                ForEach(exact.prefix(3)) { user in
                    AvatarView(user: user, size: 13)
                        .overlay(Circle().stroke(Theme.success, lineWidth: 1))
                }
                ForEach(other.prefix(3)) { user in
                    AvatarView(user: user, size: 13)
                        .opacity(0.55)
                        .overlay(Circle().stroke(Theme.warning, lineWidth: 1))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        }
    }

    private var label: String {
        var parts: [String] = []
        if !exact.isEmpty { parts.append(t("social.releases.ownedBy", ["count": exact.count])) }
        if !other.isEmpty { parts.append(t("social.releases.ownedElsewhere", ["count": other.count])) }
        return parts.joined(separator: " · ")
    }
}
