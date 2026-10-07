import SwiftUI

/// Rappel des règles officielles (Master Rule actuelle) : le contenu du web
/// (apps/web/messages/<langue>/rules.json), dans la langue de l'app. Les schémas SVG du web
/// n'ont pas d'équivalent ici : la version iOS garde le texte, les résumés et le glossaire.
struct RulesView: View {
    nonisolated struct RuleSection: Decodable, Identifiable, Sendable {
        /// Tuto vidéo (français uniquement, absent des autres langues).
        nonisolated struct Video: Decodable, Sendable {
            let id: String
            let title: String
            let channel: String
        }

        let id: String
        let group: String
        let title: String
        let icon: String
        let summary: String
        let video: Video?
        let paragraphs: [String]
        let points: [String]
        let example: String?
    }

    nonisolated struct GlossaryEntry: Decodable, Identifiable, Sendable {
        let term: String
        let definition: String
        var id: String { term }
    }

    nonisolated struct RuleLink: Decodable, Identifiable, Sendable {
        let label: String
        let detail: String
        let url: String
        var id: String { url }

        private enum CodingKeys: String, CodingKey {
            case label
            case detail = "description"
            case url
        }
    }

    /// Ordre d'affichage des groupes (les libellés viennent de `rules.groups`).
    private static let groupOrder = ["basics", "summons", "playing", "advanced"]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private let sections = L10n.shared.raw("rules.sections", as: [RuleSection].self) ?? []
    private let groups = L10n.shared.raw("rules.groups", as: [String: String].self) ?? [:]
    private let glossary = L10n.shared.raw("rules.glossary", as: [GlossaryEntry].self) ?? []
    private let links = L10n.shared.raw("rules.links", as: [RuleLink].self) ?? []

    /// Sections correspondant à la recherche (titre, résumé, texte, points, exemple).
    private var visible: [RuleSection] {
        let needle = Self.fold(query)
        guard !needle.isEmpty else { return sections }
        return sections.filter { section in
            let haystack = ([section.title, section.summary, section.example ?? ""]
                + section.paragraphs + section.points).joined(separator: " ")
            return Self.fold(haystack).contains(needle)
        }
    }

    private var visibleTerms: [GlossaryEntry] {
        let needle = Self.fold(query)
        guard !needle.isEmpty else { return glossary }
        return glossary.filter { Self.fold("\($0.term) \($0.definition)").contains(needle) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Text(t("rules.description"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if query.isEmpty { toc(proxy) }
                    if visible.isEmpty && visibleTerms.isEmpty {
                        Text(t("rules.labels.noResults"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visible) { section in
                        card(section).id(section.id)
                    }
                    if !visibleTerms.isEmpty { glossaryCard }
                    if query.isEmpty { linksCard }
                    Text(t("rules.source"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.section)
            }
        }
        .searchable(text: $query, prompt: Text(t("rules.labels.search")))
        .navigationTitle(t("rules.title"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(t("common.actions.close"), systemImage: "xmark") { dismiss() }
            }
        }
    }

    /// Sections par groupe, dans l'ordre d'affichage, groupes vides exclus.
    private struct TocGroup: Identifiable {
        let id: String
        let label: String
        let items: [RuleSection]
    }

    private var grouped: [TocGroup] {
        Self.groupOrder.compactMap { key in
            let items = sections.filter { $0.group == key }
            guard !items.isEmpty else { return nil }
            return TocGroup(id: key, label: groups[key] ?? key, items: items)
        }
    }

    /// Sommaire horizontal, regroupé comme sur le web.
    private func toc(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xs) {
                ForEach(grouped) { group in
                    Text(group.label)
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, group.id == Self.groupOrder.first ? 0 : Spacing.s)
                    ForEach(group.items) { section in
                        Button(section.title) {
                            withAnimation { proxy.scrollTo(section.id, anchor: .top) }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(t("rules.tocLabel"))
    }

    private func card(_ section: RuleSection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                SectionHeader(section.title, systemImage: Self.symbol(section.icon))
                Text(section.summary)
                    .font(.callout)
                    .foregroundStyle(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            if let video = section.video {
                videoLink(video)
            }
        }
        .surface()
    }

    /// Tuto vidéo : un simple lien, la lecture se fait dans YouTube.
    @ViewBuilder
    private func videoLink(_ video: RuleSection.Video) -> some View {
        if let url = URL(string: "https://www.youtube.com/watch?v=\(video.id)") {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(t("rules.labels.video"))
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Link(destination: url) {
                    HStack(spacing: Spacing.s) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(video.title)
                                .font(.callout.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(video.channel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var glossaryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                SectionHeader(t("rules.labels.glossary"), systemImage: "character.book.closed")
                Text(t("rules.labels.glossaryHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(visibleTerms) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.term).font(.callout.weight(.semibold))
                    Text(entry.definition)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .id("glossary")
        .surface()
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                SectionHeader(t("rules.labels.links"), systemImage: "link")
                Text(t("rules.labels.linksHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(links) { link in
                if let url = URL(string: link.url) {
                    Link(destination: url) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.label).font(.callout.weight(.medium))
                                Text(link.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .surface()
    }

    /// Recherche insensible à la casse et aux accents.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        case "Shapes": "square.on.circle"
        case "ListOrdered": "list.number"
        case "Hash": "number"
        case "Swords": "bolt.shield"
        case "Wand": "wand.and.stars"
        case "Trophy": "trophy"
        default: "book"
        }
    }
}
