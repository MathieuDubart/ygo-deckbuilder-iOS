import SwiftUI

/// Étiquettes personnelles : pastille, filtre, création, pose sur une carte ou une extension.
/// Le référentiel vit dans `AppState` — c'est une petite liste que cinq écrans affichent.

/// Le type est `nonisolated` (c'est un modèle), mais `Theme` et `t()` sont au MainActor.
@MainActor
extension TagColor {
    /// La couleur stockée est un slug, jamais une valeur : le thème reste maître de ses teintes.
    var color: Color {
        switch self {
        case .slate: .secondary
        case .red: Theme.danger
        case .amber: Theme.warning
        case .green: Theme.success
        case .teal: Theme.spell
        case .blue: .blue
        case .violet: Theme.extra
        case .pink: Theme.trap
        }
    }

    var label: String { t("tags.colors.\(rawValue)") }
}

/// Les étiquettes posées sur une cible, en lecture, dans l'ordre renvoyé par le serveur.
struct TagPills: View {
    let tagIds: [String]
    @Environment(AppState.self) private var app

    var body: some View {
        ForEach(app.tags(for: tagIds)) { tag in
            Pill(text: tag.name, tint: tag.color.color)
        }
    }
}

/// Filtre par étiquettes : on en cumule plusieurs pour restreindre (ET, pas OU — c'est ce
/// qu'on attend en empilant des critères). Un appui long sur une étiquette la supprime, et
/// la dernière puce en crée une : c'est aussi d'ici qu'on les gère.
struct TagFilterRow: View {
    @Binding var selection: [String]
    /// Effectif à montrer sur chaque pastille (cartes ou extensions selon l'onglet).
    var count: (Tag) -> Int

    @Environment(AppState.self) private var app
    @State private var creating = false
    @State private var toDelete: Tag?

    var body: some View {
        ForEach(app.tags) { tag in
            let amount = count(tag)
            FilterChip(
                isOn: selection.contains(tag.id),
                action: {
                    if let index = selection.firstIndex(of: tag.id) {
                        selection.remove(at: index)
                    } else {
                        selection.append(tag.id)
                    }
                }
            ) {
                HStack(spacing: Spacing.xxs) {
                    Circle().fill(tag.color.color).frame(width: 7, height: 7)
                    Text(tag.name)
                    if amount > 0 {
                        Text("\(amount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contextMenu {
                Button(t("common.actions.delete"), systemImage: "trash", role: .destructive) {
                    toDelete = tag
                }
            }
        }

        FilterChip(isOn: false, action: { creating = true }) {
            Label(t("tags.create"), systemImage: "plus")
        }
        .sheet(isPresented: $creating) { TagCreator() }
        .confirmationDialog(
            t("tags.confirmDelete", ["name": toDelete?.name ?? ""]),
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
            titleVisibility: .visible,
            presenting: toDelete
        ) { tag in
            Button(t("common.actions.delete"), role: .destructive) {
                Task {
                    // Retirer la puce avant de savoir si le serveur a suivi ferait croire
                    // à une suppression qui n'a pas eu lieu.
                    guard (try? await app.api.deleteTag(tag.id)) != nil else { return }
                    selection.removeAll { $0 == tag.id }
                    app.tagsChanged()
                }
            }
        }
    }
}

/// Boutons de pose d'étiquette, pour un menu (contextuel ou non).
struct TagMenuButtons: View {
    let attached: [String]
    let toggle: (Tag, Bool) async -> Void

    @Environment(AppState.self) private var app

    var body: some View {
        ForEach(app.tags) { tag in
            Button {
                Task { await toggle(tag, !attached.contains(tag.id)) }
            } label: {
                Label(tag.name, systemImage: attached.contains(tag.id) ? "checkmark" : "tag")
            }
        }
    }
}

/// Pose d'étiquettes sur une cible, avec création sur place — c'est au moment où on classe
/// qu'on sait quelle étiquette manque.
struct TagPicker: View {
    let attached: [String]
    /// Pose (`true`) ou retire l'étiquette.
    let toggle: (Tag, Bool) async -> Void

    @Environment(AppState.self) private var app
    @State private var creating = false

    var body: some View {
        Menu {
            TagMenuButtons(attached: attached, toggle: toggle)
            Divider()
            Button(t("tags.create"), systemImage: "plus") { creating = true }
        } label: {
            ChipLabel(isOn: !attached.isEmpty) {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "tag")
                    Text(t("tags.title"))
                    if !attached.isEmpty {
                        Text("\(attached.count)").font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .sheet(isPresented: $creating) { TagCreator(onCreated: toggle) }
    }
}

/// Création d'une étiquette. Si l'appelant le demande, elle est posée dans la foulée.
struct TagCreator: View {
    var onCreated: ((Tag, Bool) async -> Void)?

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: TagColor = .slate
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField(t("tags.newPlaceholder"), text: $name)
                Picker(t("tags.color"), selection: $color) {
                    ForEach(TagColor.allCases, id: \.self) { value in
                        Label {
                            Text(value.label)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(value.color)
                        }
                        .tag(value)
                    }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(t("tags.create"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.actions.cancel"), systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("tags.create"), systemImage: "checkmark") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        busy = true
        defer { busy = false }
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        guard !trimmed.isEmpty else { return }
        do {
            let tag = try await app.api.createTag(CreateTagBody(name: trimmed, color: color))
            dismiss()
            // Poser l'étiquette avant d'annoncer le changement : l'inverse déclencherait un
            // rechargement qui courrait contre la pose, et donc un second rechargement.
            await onCreated?(tag, true)
            app.tagsChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
