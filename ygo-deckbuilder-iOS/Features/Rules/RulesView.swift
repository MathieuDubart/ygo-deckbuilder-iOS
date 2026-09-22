import SwiftUI

/// Rappel des règles officielles (Master Rule actuelle) : le contenu du web
/// (apps/web/messages/<langue>/rules.json), dans la langue de l'app.
struct RulesView: View {
    nonisolated struct RuleSection: Decodable, Identifiable, Sendable {
        let id: String
        let title: String
        let icon: String
        let paragraphs: [String]
        let points: [String]
        let example: String?
    }

    @Environment(\.dismiss) private var dismiss
    private let sections = L10n.shared.raw("rules.sections", as: [RuleSection].self) ?? []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Text(t("rules.description"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    toc(proxy)
                    ForEach(sections) { section in
                        card(section).id(section.id)
                    }
                    Text(t("rules.source"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.section)
            }
        }
        .navigationTitle(t("rules.title"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
            }
        }
    }

    private func toc(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xs) {
                ForEach(sections) { section in
                    Button(section.title) {
                        withAnimation { proxy.scrollTo(section.id, anchor: .top) }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(t("rules.tocLabel"))
    }

    private func card(_ section: RuleSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(section.title, systemImage: Self.symbol(section.icon))
            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !section.points.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(t("rules.labels.points"))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                    ForEach(Array(section.points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                            Text(point)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if let example = section.example, !example.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(t("rules.labels.example"))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.spell)
                    Text(example)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.m)
                .background(Theme.spell.opacity(0.12), in: .rect(cornerRadius: Radius.s, style: .continuous))
            }
        }
        .surface()
    }

    /// Icônes lucide du web → SF Symbols.
    private static func symbol(_ lucide: String) -> String {
        switch lucide {
        case "BookOpen": "book"
        case "LayoutGrid": "square.grid.3x3"
        case "Clock": "clock"
        case "ArrowUp": "arrow.up.circle"
        case "Sparkles": "sparkles"
        case "Combine": "arrow.triangle.merge"
        case "Flame": "flame"
        case "Zap": "bolt"
        case "Layers": "square.3.layers.3d"
        case "Scale": "scalemass"
        case "Link": "link"
        case "LayoutDashboard": "rectangle.3.group"
        case "ListOrdered": "list.number"
        case "Swords": "bolt.shield"
        case "Wand": "wand.and.stars"
        default: "book"
        }
    }
}
