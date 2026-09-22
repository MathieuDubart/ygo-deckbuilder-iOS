import SwiftUI
import UniformTypeIdentifiers

/// Nouveau deck : vide, ou importé d'un fichier .ydk (fichier ou texte collé).
struct NewDeckView: View {
    var onCreated: (Deck) -> Void

    enum Mode: Hashable { case empty, ydk }

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .empty
    @State private var name = ""
    @State private var format: DeckFormat = .tcg
    @State private var ydk = ""
    @State private var picking = false
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $mode) {
                    Text(t("decks.new.modes.empty")).tag(Mode.empty)
                    Text(t("decks.new.modes.ydk")).tag(Mode.ydk)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    TextField(t("decks.new.name"), text: $name)
                    Picker(t("decks.new.format"), selection: $format) {
                        ForEach(DeckFormat.allCases) { Text(t("decks.formats.\($0.rawValue)")).tag($0) }
                    }
                }

                if mode == .ydk {
                    Section {
                        Button(t("decks.new.file"), systemImage: "doc") { picking = true }
                        TextEditor(text: $ydk)
                            .font(.caption.monospaced())
                            .frame(minHeight: 140)
                    } footer: {
                        Text(t("decks.new.fileHint"))
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(Theme.danger) }
                }
            }
            .navigationTitle(t("decks.new.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.actions.cancel"), systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t(mode == .empty ? "decks.new.submit.empty" : "decks.new.submit.ydk"), systemImage: "checkmark") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit || saving)
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.plainText, .data]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    ydk = text
                    if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (mode == .empty || !ydk.isEmpty)
    }

    private func submit() async {
        saving = true
        error = nil
        defer { saving = false }
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(80))
        do {
            let deck: Deck
            if mode == .empty {
                deck = try await app.api.createDeck(CreateDeckBody(name: trimmed, format: format))
            } else {
                deck = try await app.api.importYdk(ImportYdkBody(name: trimmed, format: format, content: ydk))
            }
            dismiss()
            onCreated(deck)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
