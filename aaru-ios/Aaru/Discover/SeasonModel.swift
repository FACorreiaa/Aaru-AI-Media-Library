import AaruAPI
import Foundation
import Observation

typealias SeasonPage = Components.Schemas.SeasonPage
typealias SeasonKind = Components.Schemas.SeasonPage.KindPayload
typealias SeasonName = Components.Schemas.SeasonPage.SeasonPayload

/// One season of one year (DISC-002): a calendar quarter, the same for every kind.
struct SeasonKey: Hashable {
    var season: SeasonName
    var year: Int

    /// The oldest year the server lists.
    static let firstYear = 1970
    /// Seasons are Gregorian quarters whatever calendar the viewer uses.
    static let calendar = Calendar(identifier: .gregorian)

    /// The season `date` falls in, in the viewer's calendar.
    static func containing(_ date: Date, calendar: Calendar = SeasonKey.calendar) -> SeasonKey {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let month = parts.month ?? 1
        return SeasonKey(season: SeasonName.allCases[(month - 1) / 3], year: parts.year ?? 2026)
    }

    func shifted(_ direction: Int) -> SeasonKey {
        let all = SeasonName.allCases
        let index = (all.firstIndex(of: season) ?? 0) + direction
        if index < 0 {
            return SeasonKey(season: .fall, year: year - 1)
        }
        if index >= all.count {
            return SeasonKey(season: .winter, year: year + 1)
        }
        return SeasonKey(season: all[index], year: year)
    }

    /// Whether a step that way stays between 1970 and the year after this one.
    func canShift(_ direction: Int, now: Date = .now, calendar: Calendar = SeasonKey.calendar) -> Bool {
        let next = shifted(direction)
        return next.year >= Self.firstYear && next.year <= calendar.component(.year, from: now) + 1
    }

    /// "Fall 2026": the year never grouped.
    var title: String {
        "\(season.rawValue.capitalized) \(String(year))"
    }

    /// "Oct – Dec".
    var months: String {
        var calendar = Self.calendar
        calendar.locale = .current
        let symbols = calendar.shortMonthSymbols
        let first = (SeasonName.allCases.firstIndex(of: season) ?? 0) * 3
        return "\(symbols[first]) – \(symbols[first + 2])"
    }

    /// Orders seasons in time, for the side a new one slides in from.
    var order: Int {
        year * 4 + (SeasonName.allCases.firstIndex(of: season) ?? 0)
    }
}

extension SeasonKind: @retroactive Identifiable {
    public var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .anime: "Anime"
        case .showsNew: "New shows"
        case .showsReturning: "Returning"
        case .movies: "Movies"
        }
    }

    /// "84 anime", "1 new show", "9,870 films".
    func count(_ total: Int) -> String {
        let noun = switch self {
        case .anime: "anime"
        case .showsNew: total == 1 ? "new show" : "new shows"
        case .showsReturning: total == 1 ? "returning show" : "returning shows"
        case .movies: total == 1 ? "film" : "films"
        }
        return "\(total.formatted()) \(noun)"
    }

    var provider: String {
        self == .anime ? "AniList" : "TMDB"
    }
}

/// The Seasons view's state: which season and kind, every page fetched this visit (so flipping
/// back is instant), and adds in flight. Catalog data, the same for every user.
@MainActor
@Observable
final class SeasonModel {
    struct Query: Hashable {
        var kind: SeasonKind
        var key: SeasonKey
    }

    var kind: SeasonKind = .anime
    var key: SeasonKey
    private(set) var pages: [String: SeasonPage] = [:]
    /// How many pages of the current season are shown.
    private(set) var shown = 1
    /// Pages being fetched, by cache key: a fetch for another season never waits on this one.
    private(set) var loading: Set<String> = []
    /// Pages whose last fetch failed, by cache key: shown in place, on that season only.
    private(set) var failed: Set<String> = []
    private(set) var adding: Set<String> = []
    /// An add that failed; season loads report through `firstFailed` instead.
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let library: LibraryModel?

    init(api: Client?, library: LibraryModel?, now: Date = .now) {
        self.api = api
        self.library = library
        key = SeasonKey.containing(now)
    }

    /// For previews: one page in place, nothing to fetch.
    convenience init(preview page: SeasonPage) {
        self.init(api: nil, library: nil)
        key = SeasonKey(season: page.season, year: page.year)
        kind = page.kind
        pages[Self.pageKey(kind, key, 1)] = page
    }

    var isLoading: Bool {
        loading.contains(Self.pageKey(kind, key, shown)) || loading.contains(Self.pageKey(kind, key, shown + 1))
    }

    var query: Query {
        Query(kind: kind, key: key)
    }

    var first: SeasonPage? {
        pages[Self.pageKey(kind, key, 1)]
    }

    /// Whether the current season's first page could not be loaded.
    var firstFailed: Bool {
        first == nil && failed.contains(Self.pageKey(kind, key, 1))
    }

    /// The shown pages' titles, each once: popularity can move a title onto the next page.
    var items: [CatalogHit] {
        var seen: Set<String> = []
        return (1 ... shown).compactMap { pages[Self.pageKey(kind, key, $0)] }
            .flatMap(\.items)
            .filter { seen.insert($0.id).inserted }
    }

    var hasMore: Bool {
        pages[Self.pageKey(kind, key, shown)]?.hasMore ?? false
    }

    /// "Oct – Dec · 84 anime".
    var detail: String {
        [key.months, first?.total.map { kind.count($0) }].compactMap(\.self).joined(separator: " · ")
    }

    /// The first page of the current season, unless it is already here.
    func load() async {
        shown = 1
        await fetch(page: 1)
    }

    /// Fetches the current season again, dropping what was cached (Try again, pull to refresh).
    func reload() async {
        let prefix = Self.pageKey(kind, key, 0).dropLast()
        for cached in pages.keys where cached.hasPrefix(prefix) {
            pages[cached] = nil
        }
        failed = failed.filter { !$0.hasPrefix(prefix) }
        await load()
    }

    func loadMore() async {
        let next = shown + 1
        await fetch(page: next)
        if pages[Self.pageKey(kind, key, next)] != nil {
            shown = next
        }
    }

    func libraryItemID(_ hit: CatalogHit) -> String? {
        hit.libraryItemId ?? library?.entry(matching: hit)?.id
    }

    /// Adds a hit with a status, as Discover's rows do.
    func add(_ hit: CatalogHit, status: LibraryStatus) async {
        guard let api, let library, !adding.contains(hit.id) else { return }
        problem = nil
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        problem = await library.add(hit, status: status, api: api)
    }

    private func fetch(page: Int) async {
        let cacheKey = Self.pageKey(kind, key, page)
        guard let api, pages[cacheKey] == nil, !loading.contains(cacheKey),
              let queryKind = Operations.GetDiscoverSeason.Input.Query.KindPayload(rawValue: kind.rawValue),
              let querySeason = Operations.GetDiscoverSeason.Input.Query.SeasonPayload(rawValue: key.season.rawValue)
        else { return }
        loading.insert(cacheKey)
        failed.remove(cacheKey)
        defer { loading.remove(cacheKey) }
        do {
            switch try await api.getDiscoverSeason(query: .init(
                kind: queryKind, season: querySeason, year: key.year, page: page
            )) {
            case let .ok(response):
                pages[cacheKey] = try response.body.json
            case .default:
                failed.insert(cacheKey)
            }
        } catch {
            // Stepping on before a season arrives cancels its fetch; that is not a failure.
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            failed.insert(cacheKey)
        }
    }

    static func pageKey(_ kind: SeasonKind, _ key: SeasonKey, _ page: Int) -> String {
        "\(kind.rawValue):\(key.year)-\(key.season.rawValue):\(page)"
    }
}
