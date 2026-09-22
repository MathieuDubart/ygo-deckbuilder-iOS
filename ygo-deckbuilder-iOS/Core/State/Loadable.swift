import SwiftUI

/// État d'un chargement.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension Loadable {
    /// Résultat d'un chargement. Pendant un rechargement, l'ancienne valeur reste affichée ;
    /// si le rechargement échoue, on la garde. Usage : `state = await .fetch(state) { … }`.
    static func fetch(_ previous: Loadable, _ work: () async throws -> Value) async -> Loadable {
        do {
            return .loaded(try await work())
        } catch is CancellationError {
            return previous
        } catch let error as URLError where error.code == .cancelled {
            return previous
        } catch {
            return previous.value == nil ? .failed(error.localizedDescription) : previous
        }
    }
}

/// Affiche chargement / erreur (avec « Réessayer ») / contenu.
struct LoadableView<Value, Content: View>: View {
    let state: Loadable<Value>
    var retry: (() async -> Void)?
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        case .failed(let message):
            ContentUnavailableView {
                Label(t("common.status.error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                if let retry {
                    Button(t("common.actions.retry")) { Task { await retry() } }
                        .buttonStyle(.glass)
                }
            }
        case .loaded(let value):
            content(value)
        }
    }
}
