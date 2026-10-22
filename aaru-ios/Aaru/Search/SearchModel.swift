import AaruAPI
import Foundation
import Observation

/// Search's state (APP-004): the query and scope, the hits, and the adds in flight. The view
/// only draws it; requests go through here.
@MainActor
@Observable
final class SearchModel {
    var query = ""
    var scope = SearchScope.all
    private(set) var hits: [CatalogHit] = []
    private(set) var incomplete = false
    private(set) var notice: String?
    private(set) var isSearching = false
    var problem: String?
    /// Hits being added right now: a second tap waits instead of adding twice.
    private(set) var adding: Set<String> = []

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private let lists: ListsModel
    /// Pick mode's year (IMP-011): hits from it come first.
    @ObservationIgnored private let year: Int?

    init(api: Client?, library: LibraryModel, lists: ListsModel, pick: SearchPick? = nil) {
        self.api = api
        self.library = library
        self.lists = lists
        year = pick?.year
        query = pick?.query ?? ""
        scope = pick?.scope ?? .all
    }

    struct Key: Equatable {
        let query: String
        let scope: SearchScope
    }

    /// What the search task restarts on.
    var key: Key {
        Key(query: query, scope: scope)
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    func search() async {
        let text = trimmedQuery
        guard text.count >= 2, let api else {
            hits = []
            incomplete = false
            problem = nil
            return
        }
        // Debounce: a new keystroke cancels this task before the request goes out.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            switch try await api.searchCatalog(query: .init(q: text, _type: scope.searchType)) {
            case let .ok(response):
                let results = try response.body.json
                hits = results.items
                if let year {
                    // Stable: the catalog's order holds within each group.
                    hits = hits.filter { $0.year == year } + hits.filter { $0.year != year }
                }
                incomplete = results.incomplete
                notice = results.notice
                problem = nil
            case let .default(_, error):
                hits = []
                incomplete = false
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

    func add(_ hit: CatalogHit, status: LibraryStatus) async {
        guard !adding.contains(hit.id) else { return }
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        if let failure = await library.add(hit, status: status, api: api) {
            problem = failure
        }
    }

    /// Pick mode (IMP-011): saves the choice. True once it is saved and the sheet can close.
    func choose(_ hit: CatalogHit, for pick: SearchPick) async -> Bool {
        guard adding.isEmpty else { return false }
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        if let failure = await pick.choose(hit) {
            problem = failure
            return false
        }
        return true
    }

    /// List mode (LST-003): adds the hit to `list` and returns the list as it is now, or nil.
    func add(_ hit: CatalogHit, to list: ListDetail) async -> ListDetail? {
        guard !adding.contains(hit.id) else { return nil }
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        let ref = MediaRef(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year)
        if let updated = await lists.add(ref, to: list.id) {
            return updated
        }
        problem = lists.problem ?? "\(hit.title) could not be added to \(list.name)."
        lists.problem = nil
        return nil
    }
}
