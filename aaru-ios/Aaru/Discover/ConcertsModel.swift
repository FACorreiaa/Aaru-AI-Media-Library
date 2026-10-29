import AaruAPI
import Foundation
import Observation

/// Concerts on Discover (MUS-003): upcoming concerts by the artists of the user's albums, and
/// concerts within a radius of the saved "Concerts near" city or of a one-off approximate
/// location. Catalog data from Ticketmaster, linked out for tickets. Also the "Concerts near"
/// setting itself, which Settings edits through the same model. MUS-010 narrows the Near list
/// to one artist's concerts, near the same centre or anywhere.
@MainActor
@Observable
final class ConcertsModel {
    enum NearState: Equatable {
        case idle, loading, loaded, noPlace, failed
    }

    enum Layout: String, CaseIterable, Identifiable {
        case list, map

        var id: String {
            rawValue
        }

        var label: String {
            self == .list ? "List" : "Map"
        }

        var systemImage: String {
            self == .list ? "list.bullet" : "map"
        }
    }

    /// What the Near list was fetched for; a change fetches it again.
    struct Query: Hashable {
        var radius: ConcertRadius
        var point: ConcertPoint?
        var place: ConcertPlace?
        var artist: ArtistSearch?
        var scope: ConcertSearchScope?
    }

    /// The shortest artist name a search sends; the server refuses less.
    static let minSearch = 2

    private(set) var setting: Components.Schemas.ConcertPlaceSetting?
    var radius: ConcertRadius = ._50
    var layout: Layout = .list
    /// "Use my location"'s point, in memory only.
    private(set) var point: ConcertPoint?
    private(set) var pages: [ConcertPage] = []
    private(set) var nearState: NearState = .idle
    private(set) var isLoadingMore = false
    private(set) var artists: ArtistConcerts?
    private(set) var artistsFailed = false
    private(set) var isLocating = false
    var problem: String?
    /// The search field. Only a submitted name searches: each search spends the provider's
    /// daily calls.
    var searchText = ""
    /// The artist the Near list is narrowed to, once picked.
    private(set) var searchedArtist: ArtistSearch?
    private(set) var performerChoices: PerformerChoices?
    var scope: ConcertSearchScope = .near

    @ObservationIgnored let api: Client?
    @ObservationIgnored private var loadedQuery: Query?

    init(api: Client?) {
        self.api = api
    }

    /// For previews: everything in place, nothing to fetch.
    convenience init(
        preview setting: Components.Schemas.ConcertPlaceSetting,
        near: ConcertPage?,
        artists: ArtistConcerts?
    ) {
        self.init(api: nil)
        self.setting = setting
        self.artists = artists
        if let near {
            pages = [near]
            nearState = .loaded
            loadedQuery = query
        }
    }

    /// Whether this server has concerts at all; Discover hides the view when not.
    var available: Bool {
        setting?.available ?? false
    }

    var savedPlace: ConcertPlace? {
        setting?.place
    }

    var query: Query {
        Query(
            radius: radius, point: point, place: savedPlace, artist: searchedArtist,
            scope: searchedArtist == nil ? nil : scope
        )
    }

    /// Every fetched page's concerts, each once.
    var nearItems: [Concert] {
        var seen: Set<String> = []
        return pages.flatMap(\.items).filter { seen.insert($0.id).inserted }
    }

    var hasMore: Bool {
        pages.last?.hasMore ?? false
    }

    var nearUnavailable: Bool {
        pages.first?.unavailable ?? false
    }

    var usesLocation: Bool {
        point != nil
    }

    /// The centre the Near list was searched around, for the map.
    var centre: (name: String, point: ConcertPoint)? {
        if let point {
            return ("Your approximate location", point)
        }
        guard let place = pages.first?.place ?? savedPlace else { return nil }
        return (place.name, ConcertPoint(latitude: place.latitude, longitude: place.longitude))
    }

    // MARK: Loading

    /// The saved city and whether concerts are on. A failure leaves concerts hidden.
    func loadSetting() async {
        guard let api, case let .ok(response) = try? await api.getConcertPlace(),
              let setting = try? response.body.json
        else { return }
        self.setting = setting
    }

    func loadArtists(force: Bool = false) async {
        guard let api, available, force || artists == nil else { return }
        artistsFailed = false
        do {
            switch try await api.getArtistConcerts() {
            case let .ok(response):
                artists = try response.body.json
            case .default:
                artistsFailed = artists == nil
            }
        } catch {
            if !Self.isCancellation(error) {
                artistsFailed = artists == nil
            }
        }
    }

    /// When the Concerts view appears: the setting again (Settings may have changed the city since
    /// it was last shown), then the artists unless they are already here.
    func appear() async {
        await loadSetting()
        await loadArtists()
    }

    /// The first page around the current centre, unless it is already here.
    func loadNear(force: Bool = false) async {
        guard api != nil, setting != nil else { return }
        let query = query
        if !force, loadedQuery == query, nearState == .loaded {
            return
        }
        // Anywhere needs no centre; everything else does.
        guard point != nil || savedPlace != nil || searchesAnywhere else {
            pages = []
            nearState = .noPlace
            loadedQuery = query
            return
        }
        pages = []
        nearState = .loading
        switch await fetch(page: 1) {
        case let .page(page):
            pages = [page]
            nearState = .loaded
            loadedQuery = query
        case .noPlace:
            nearState = .noPlace
            loadedQuery = query
        case .failed:
            nearState = .failed
        case .cancelled:
            break
        }
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let query = query
        switch await fetch(page: pages.count + 1) {
        case let .page(page) where query == self.query:
            pages.append(page)
        case .failed:
            problem = "More concerts could not be loaded."
        default:
            break
        }
    }

    /// Pull to refresh and Try again: both sections, fetched again.
    func reload() async {
        await loadSetting()
        async let artists: Void = loadArtists(force: true)
        await loadNear(force: true)
        await artists
    }

    // MARK: Location

    /// One approximate fix, rounded, kept for this visit only.
    func useMyLocation() async {
        guard !isLocating else { return }
        isLocating = true
        defer { isLocating = false }
        do {
            point = try await ApproximateLocation.current()
            problem = nil
        } catch ApproximateLocation.Failure.denied {
            problem = "Aaru can't use your location. Allow it in Settings, or choose a city."
        } catch {
            problem = "Your location could not be found. Try again, or choose a city."
        }
    }

    /// Back to the saved city.
    func useSavedPlace() {
        point = nil
    }

    // MARK: The saved city

    /// Up to eight cities for what was typed; nil when the search failed.
    func searchPlaces(_ text: String) async -> [ConcertPlace]? {
        guard let api else { return [] }
        do {
            switch try await api.searchConcertPlaces(query: .init(q: text)) {
            case let .ok(response):
                return try response.body.json.items
            case .default:
                return nil
            }
        } catch {
            return nil
        }
    }

    /// Saves the "Concerts near" city and looks around it. Returns whether it was saved.
    func choose(_ place: ConcertPlace) async -> Bool {
        guard let api else { return false }
        do {
            switch try await api.saveConcertPlace(body: .json(place)) {
            case let .ok(response):
                setting = try response.body.json
                point = nil
                problem = nil
                return true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That city was not saved."
            }
        } catch {
            problem = "That city was not saved. Aaru could not reach the server."
        }
        return false
    }

    /// Forgets the saved city.
    func removePlace() async {
        guard let api else { return }
        do {
            switch try await api.deleteConcertPlace() {
            case .noContent:
                setting?.place = nil
                problem = nil
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "The city was not removed."
            }
        } catch {
            problem = "The city was not removed. Aaru could not reach the server."
        }
    }

    // MARK: Fetching

    private func fetch(page: Int) async -> ConcertFetch {
        guard let api else { return .cancelled }
        let fetcher = ConcertsFetcher(api: api, point: point, radius: radius)
        do {
            if let artist = searchedArtist {
                return try await fetcher.search(artist, scope: scope, page: page)
            }
            return try await fetcher.near(page: page)
        } catch {
            return Self.isCancellation(error) ? .cancelled : .failed
        }
    }

    /// A newer search (another radius, another centre) cancels the one in flight: not a failure.
    private static func isCancellation(_ error: any Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

// MARK: Search by artist (MUS-010)

extension ConcertsModel {
    /// An artist searched for anywhere: no radius, no map.
    var searchesAnywhere: Bool {
        searchedArtist != nil && scope == .anywhere
    }

    /// "Near Lisboa", "Near you"; "Radiohead near Lisboa", "Radiohead anywhere" while searching.
    var nearTitle: String {
        guard let artist = searchedArtist?.name else { return nearScopeLabel }
        return scope == .anywhere ? "\(artist) anywhere" : "\(artist) near \(centreName ?? "you")"
    }

    /// "Near Lisboa", "Near you": the section's title, and the search's Near scope.
    var nearScopeLabel: String {
        centreName.map { "Near \($0)" } ?? "Near you"
    }

    /// The city the list is around; nil for a one-off position or no city.
    private var centreName: String? {
        point == nil ? (pages.first?.place ?? savedPlace)?.name : nil
    }

    /// Performers for the name first; with none to offer, straight to every event matching it.
    func submitSearch() async {
        let name = String(searchText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard name.count >= Self.minSearch, let api else { return }
        performerChoices = .loading(name)
        let fetcher = ConcertsFetcher(api: api, point: point, radius: radius)
        // A failed lookup still searches the name.
        let found = await (try? fetcher.performers(name)) ?? []
        // Another name, a pick or Clear came first.
        guard performerChoices == .loading(name) else { return }
        if found.isEmpty {
            chooseAll(name)
        } else {
            performerChoices = .ready(name, found)
        }
    }

    func choose(_ performer: ConcertPerformer) {
        performerChoices = nil
        searchText = performer.name
        searchedArtist = ArtistSearch(name: performer.name, performerID: performer.id)
    }

    /// Every event matching the name, for festivals and bills without a named act.
    func chooseAll(_ name: String) {
        performerChoices = nil
        searchedArtist = ArtistSearch(name: name)
    }

    /// Back to everything near.
    func clearSearch() {
        performerChoices = nil
        searchedArtist = nil
    }
}
