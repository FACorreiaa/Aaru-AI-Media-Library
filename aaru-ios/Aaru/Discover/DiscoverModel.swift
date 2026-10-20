import AaruAPI
import Foundation
import Observation

/// Discover (CAT-020, APP-012, DISC-001): trending, this season, new and in theaters, as the
/// rows `/v1/discover` returns, titled by the server. Catalog data, the same for every user: not
/// a recommendation. The last good load shares Home's Discover file, so the tab opens offline.
@MainActor
@Observable
final class DiscoverModel {
    private(set) var rows: [DiscoverRow] = []
    /// Hits being added right now, by hit id.
    private(set) var adding: Set<String> = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let library: LibraryModel?
    @ObservationIgnored private let cache: HomeCache?

    init(api: Client?, library: LibraryModel?, cache: HomeCache? = HomeCache()) {
        self.api = api
        self.library = library
        self.cache = cache
        rows = cache?.loadDiscover() ?? []
    }

    /// For previews: rows already in place, nothing to fetch.
    convenience init(preview rows: [DiscoverRow]) {
        self.init(api: nil, library: nil, cache: nil)
        self.rows = rows
        hasLoaded = true
    }

    /// Rows with something to show, in the server's order.
    var visibleRows: [DiscoverRow] {
        rows.filter { !$0.items.isEmpty }
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        guard let api, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            switch try await api.getDiscover() {
            case let .ok(response):
                rows = try response.body.json.rows
                cache?.saveDiscover(rows)
                hasLoaded = true
                problem = nil
            case .default:
                problem = rows.isEmpty
                    ? "Discover is not available right now."
                    : "Discover could not be refreshed. Showing the last lists."
            }
        } catch {
            problem = rows.isEmpty
                ? "Aaru could not reach the server."
                : "Offline. Showing Discover from the last load."
        }
    }

    /// The library item a hit opens: the server's mark, else a match on the shelf (it may have
    /// been added since the rows loaded).
    func libraryItemID(_ hit: CatalogHit) -> String? {
        hit.libraryItemId ?? library?.entry(matching: hit)?.id
    }

    /// Adds a hit with a status, as search does. The shelf's revision goes up, so Home reloads.
    func add(_ hit: CatalogHit, status: LibraryStatus) async {
        guard let api, let library, !adding.contains(hit.id) else { return }
        problem = nil
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        problem = await library.add(hit, status: status, api: api)
    }
}
