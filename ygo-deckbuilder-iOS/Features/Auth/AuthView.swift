import SwiftUI

/// Connexion / création de compte (mêmes règles que le web : cf. registerSchema).
struct AuthView: View {
    enum Mode: Hashable { case login, register }

    @Environment(AppState.self) private var app
    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var submitting = false
    @State private var error: String?
    @State private var showsValidation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t(mode == .login ? "auth.login.title" : "auth.register.title"))
                            .font(.largeTitle.bold())
                        Text(t("layout.metaDescription"))
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    Picker("", selection: $mode) {
                        Text(t("layout.pages.login")).tag(Mode.login)
                        Text(t("layout.pages.register")).tag(Mode.register)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    field(t("auth.fields.email"), error: emailError) {
                        TextField(t("auth.fields.email"), text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if mode == .register {
                        field(t("auth.fields.username"), error: usernameError) {
                            TextField(t("auth.fields.username"), text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    field(t("auth.fields.password"), error: passwordError) {
                        SecureField(t("auth.fields.password"), text: $password)
                            .textContentType(mode == .login ? .password : .newPassword)
                    }
                } footer: {
                    if mode == .register {
                        Text(t("auth.fields.passwordHint"))
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if submitting {
                                ProgressView()
                            } else {
                                Text(t(mode == .login ? "auth.login.submit" : "auth.register.submit"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(submitting)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    LabeledContent(t("ios.server.current"), value: app.server.url?.host() ?? "—")
                    Button(t("ios.server.change"), role: .destructive) {
                        Task { await app.forgetServer() }
                    }
                }
            }
            .animation(.default, value: mode)
            .onChange(of: mode) {
                error = nil
                showsValidation = false
            }
        }
    }

    @ViewBuilder
    private func field(_ label: String, error: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            if showsValidation, let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    // MARK: - Validation (registerSchema / loginSchema)

    private var emailError: String? {
        let e = email.trimmingCharacters(in: .whitespaces)
        let valid = e.wholeMatch(of: #/[^@\s]+@[^@\s]+\.[^@\s]+/#) != nil
        return valid ? nil : t("auth.errors.email")
    }

    private var usernameError: String? {
        guard mode == .register else { return nil }
        if !(3...32).contains(username.count) { return t("auth.errors.usernameLength") }
        if username.wholeMatch(of: #/[A-Za-z0-9_-]+/#) == nil { return t("auth.errors.usernameChars") }
        return nil
    }

    private var passwordError: String? {
        if mode == .login { return password.isEmpty ? t("auth.errors.passwordRequired") : nil }
        if password.count < 10 { return t("auth.errors.passwordLength") }
        if password.count > 128 { return t("auth.errors.passwordMax") }
        return nil
    }

    private func submit() async {
        showsValidation = true
        guard emailError == nil, usernameError == nil, passwordError == nil else { return }
        submitting = true
        error = nil
        defer { submitting = false }
        do {
            let mail = email.trimmingCharacters(in: .whitespaces)
            switch mode {
            case .login:
                try await app.login(email: mail, password: password)
            case .register:
                try await app.register(email: mail, username: username, password: password)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
