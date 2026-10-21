import AaruAPI
import Foundation
import Observation

typealias Concert = Components.Schemas.Concert
typealias ConcertPlace = Components.Schemas.ConcertPlace
typealias ConcertPage = Components.Schemas.ConcertPage
typealias ArtistConcerts = Components.Schemas.ArtistConcerts
typealias ConcertRadius = Components.Schemas.ConcertsNearRequest.RadiusKmPayload

/// A point to look for concerts around, rounded to two decimals (about a kilometre). "Use my
/// location" keeps one in memory for this visit only: it is never saved, here or on the server.
struct ConcertPoint: Hashable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
    }
}

extension ConcertPlace {
    /// "Lisboa, Lisbon, Portugal": the parts there are, each once.
    var label: String {
        [name, detail].compactMap(\.self).joined(separator: ", ")
    }

    /// A row's identity in the city picker: name and point, compact.
    var key: String {
        "\(name)|\(latitude)|\(longitude)"
    }

    /// "Lisbon, Portugal", or nil when the place has nothing past its name.
    var detail: String? {
        let parts = [region, country].compactMap(\.self).filter { !$0.isEmpty && $0 != name }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

extension ConcertRadius {
    /// "50 km": the API's unit, the same in every locale.
    var label: String {
        "\(rawValue) km"
    }

    var spoken: String {
        "\(rawValue) kilometres"
    }
}

/// Concerts on Discover (MUS-003): upcoming concerts by the artists of the user's albums, and
/// concerts within a radius of the saved "Concerts near" city or of a one-off approximate
/// location. Catalog data from Ticketmaster, linked out for tickets. Also the "Concerts near"
/// setting itself, which Settings edits through the same model.
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
    }

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

    @ObservationIgnored private let api: Client?
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
        Query(radius: radius, point: point, place: savedPlace)
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

    /// "Near Lisboa", "Near you".
    var nearTitle: String {
        if point != nil {
            return "Near you"
        }
        return (pages.first?.place ?? savedPlace).map { "Near \($0.name)" } ?? "Near you"
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
        guard point != nil || savedPlace != nil else {
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

    private enum Fetched {
        case page(ConcertPage), noPlace, failed, cancelled
    }

    private func fetch(page: Int) async -> Fetched {
        guard let api else { return .cancelled }
        let body = Components.Schemas.ConcertsNearRequest(
            latitude: point?.latitude, longitude: point?.longitude, radiusKm: radius, page: page
        )
        do {
            switch try await api.getConcertsNear(body: .json(body)) {
            case let .ok(response):
                let page = try response.body.json
                return Task.isCancelled ? .cancelled : .page(page)
            case let .default(statusCode, error):
                if statusCode == 409, (try? error.body.json.code) == "no_place" {
                    return .noPlace
                }
                return .failed
            }
        } catch {
            return Self.isCancellation(error) ? .cancelled : .failed
        }
    }

    /// A newer search (another radius, another centre) cancels the one in flight: not a failure.
    private static func isCancellation(_ error: any Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
