import SwiftUI

/// Premier lancement : l'adresse de son instance (auto-hébergée ou non).
struct ServerSetupView: View {
    @Environment(AppState.self) private var app
    @State private var address = ""
    @State private var checking = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .padding(.top, 32)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("ios.server.title"))
                            .font(.largeTitle.bold())
                        Text(t("ios.server.description"))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TextField(t("ios.server.placeholder"), text: $address)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($focused)
                            .onSubmit { Task { await connect() } }
                            .padding(14)
                            .background(.fill.tertiary, in: .rect(cornerRadius: 14))
                        Text(t("ios.server.hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(Theme.danger)
                    }

                    Button {
                        Task { await connect() }
                    } label: {
                        Group {
                            if checking {
                                ProgressView()
                            } else {
                                Text(t("ios.server.connect"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { focused = true }
        }
    }

    private func connect() async {
        guard let url = ServerConfig.normalize(address) else {
            error = t("ios.server.invalid")
            return
        }
        checking = true
        error = nil
        defer { checking = false }
        do {
            try await app.api.checkServer(url)
            app.useServer(url)
        } catch {
            self.error = t("ios.server.unreachable", ["url": url.absoluteString, "error": error.localizedDescription])
        }
    }
}
