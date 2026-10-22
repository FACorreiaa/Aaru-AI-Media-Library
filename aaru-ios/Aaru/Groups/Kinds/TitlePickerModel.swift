import AaruAPI
import Foundation
import Observation

/// The catalog search behind `TitlePickerSheet`: one query and kind at a time, debounced by the
/// caller's task. Picking never touches the library.
@MainActor
@Observable
final class TitlePickerModel {
    private(set) var hits: [CatalogHit] = []
    private(set) var isSearching = false
    var problem: String?

    @ObservationIgnored private let api: Client?

    init(api: Client?) {
        self.api = api
    }

    /// Searches after a short pause; a newer call cancels this one's task before the request.
    func search(_ query: String, kind: MediaKind) async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, let api else {
            hits = []
            problem = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            switch try await api.searchCatalog(query: .init(q: text, _type: kind.searchType)) {
            case let .ok(response):
                hits = try response.body.json.items
                problem = nil
            case let .default(_, error):
                hits = []
                problem = (try? error.body.json.message) ?? "Search is not available right now."
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                problem = "Aaru could not reach the server."
            }
        }
    }
}
