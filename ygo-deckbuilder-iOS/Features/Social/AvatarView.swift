import SwiftUI

/// Avatar d'un compte. Sans image, l'initiale du pseudo sur une couleur déduite de ce même
/// pseudo : deux comptes restent distinguables, et il n'y a jamais de trou.
struct AvatarView: View {
    let user: PublicProfile
    var size: CGFloat = 32

    @Environment(AppState.self) private var app

    var body: some View {
        RemoteImage([app.api.absoluteURL(user.avatarUrl)], width: .thumb, optimized: false) {
            Circle()
                .fill(Self.tint(user.username))
                .overlay {
                    Text(user.initial)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        // `clipShape` ne retire pas les coins du test de toucher : sans ça, l'avatar
        // intercepterait les appuis dans ses angles.
        .contentShape(.circle)
    }

    /// Teinte stable déduite du pseudo. Saturation et luminosité fixes : l'initiale blanche
    /// reste lisible quelle que soit la teinte tirée.
    static func tint(_ username: String) -> Color {
        var hash = 0
        for scalar in username.unicodeScalars { hash = (hash &* 31 &+ Int(scalar.value)) % 360 }
        return Color(hue: Double(hash) / 360, saturation: 0.45, brightness: 0.62)
    }
}

/// Avatar + pseudo, la ligne la plus répétée de la fonctionnalité.
struct UserRow: View {
    let user: PublicProfile
    var size: CGFloat = 36
    var subtitle: String?

    var body: some View {
        HStack(spacing: Spacing.m) {
            AvatarView(user: user, size: size)
            VStack(alignment: .leading, spacing: 1) {
                Text(user.username).font(.subheadline.weight(.medium)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
