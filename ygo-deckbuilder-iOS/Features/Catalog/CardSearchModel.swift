import Foundation
import Observation

/// Recherche paginée dans le catalogue (GET /cards), avec anti-rebond et défilement infini.
@Observable
final class CardSearchModel {
    var query: CardSearchQuery {
        didSet { if query != oldValue { scheduleSearch() } }
    }

    private(set) var items: [CardSummary] = []
    private(set) var total = 0
    private(set) var approximate = false
    private(set) var loading = false
    private(set) var error: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var page = 1
    @ObservationIgnored private var totalPages = 1
    @ObservationIgnored private var task: Task<Void, Never>?

    init(api: APIClient, query: CardSearchQuery = CardSearchQuery()) {
        self.api = api
        self.query = query
    }

    var canLoadMore: Bool { page < totalPages && !loading }

    private func scheduleSearch() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    func reload() async {
        loading = true
        defer { loading = false }
        error = nil
        var q = query
        q.page = 1
        do {
            let result = try await api.searchCards(q)
            guard !Task.isCancelled, q.withoutPage == query.withoutPage else { return }
            items = result.items
            total = result.total
            page = result.page
            totalPages = result.totalPages
            approximate = result.approximate ?? false
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard canLoadMore else { return }
        loading = true
        defer { loading = false }
        var q = query
        q.page = page + 1
        if let result = try? await api.searchCards(q), q.withoutPage == query.withoutPage {
            let known = Set(items.map(\.id))
            items += result.items.filter { !known.contains($0.id) }
            page = result.page
            totalPages = result.totalPages
        }
    }
}

extension CardSearchQuery {
    /// Même recherche, quelle que soit la page.
    var withoutPage: CardSearchQuery {
        var copy = self
        copy.page = 1
        return copy
    }
}
