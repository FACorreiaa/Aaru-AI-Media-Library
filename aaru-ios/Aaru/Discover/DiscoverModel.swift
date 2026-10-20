import AaruAPI
import Foundation
import Observation

typealias DiscoverFeed = Components.Schemas.Discover
typealias DiscoverSection = Components.Schemas.DiscoverSection

/// Discover (CAT-020, APP-012): what is trending, coming to cinemas, new and airing, from
/// `/v1/discover`. Catalog data, the same for every user: not a recommendation. The last good
/// load is cached so the screen opens offline.
@MainActor
@Observable
final class DiscoverModel {
    private(set) var sections: [DiscoverSection] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let cache: DiscoverCache?

    init(api: Client?, cache: DiscoverCache? = DiscoverCache()) {
        self.api = api
        self.cache = cache
        if let cached = cache?.load() {
            sections = cached.sections
        }
    }

    /// For previews: sections already in place, nothing to fetch.
    convenience init(preview feed: DiscoverFeed) {
        self.init(api: nil, cache: nil)
        sections = feed.sections
        hasLoaded = true
    }

    /// Sections with something to show, in the server's order.
    var visibleSections: [DiscoverSection] {
        sections.filter { !$0.items.isEmpty }
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
            switch try await api.getDiscover(query: .init()) {
            case let .ok(response):
                let feed = try response.body.json
                sections = feed.sections
                cache?.save(feed)
                hasLoaded = true
                problem = nil
            case .default:
                problem = sections.isEmpty
                    ? "Discover is not available right now."
                    : "Discover could not be refreshed. Showing the last lists."
            }
        } catch {
            problem = sections.isEmpty
                ? "Aaru could not reach the server."
                : "Offline. Showing Discover from the last load."
        }
    }

    // MARK: Labels

    /// "Trending this week", "Anime · Fall 2026".
    static func title(for section: DiscoverSection) -> String {
        switch section.id {
        case .trending: "Trending this week"
        case .upcomingMovies: "Coming to cinemas"
        case .newShows: "New shows"
        case .onTheAir: "Airing this week"
        case .animeSeason: section.animeSeason.map(animeTitle) ?? "Anime this season"
        case .animeNextSeason: section.animeSeason.map(animeTitle) ?? "Anime next season"
        }
    }

    private static func animeTitle(_ season: Components.Schemas.AnimeSeason) -> String {
        "Anime · \(season.season.rawValue.capitalized) \(season.year)"
    }

    /// Whether a section's cards carry a release-date badge. Trending is about now, not a date.
    static func showsDates(_ section: DiscoverSection) -> Bool {
        section.id != .trending
    }

    /// "Out now", "Today", "Tomorrow", "In 3 days", "Nov 14" from a `YYYY-MM-DD` release date.
    /// Nil when there is no date or it cannot be read.
    static func dateBadge(_ releaseDate: String?, now: Date = .now, calendar: Calendar = .current) -> String? {
        let parts = releaseDate?.split(separator: "-").compactMap { Int($0) } ?? []
        guard parts.count == 3,
              let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 0
        switch days {
        case ..<0: return "Out now"
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2 ... 6: return "In \(days) days"
        default:
            let sameYear = calendar.component(.year, from: now) == parts[0]
            return day.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).year())
        }
    }
}

/// The last Discover load on disk. It holds no user data, so sign-out leaves it.
struct DiscoverCache {
    let url: URL

    init(fileManager: FileManager = .default) {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        url = base.appendingPathComponent("discover.json")
    }

    func load() -> DiscoverFeed? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DiscoverFeed.self, from: data)
    }

    func save(_ feed: DiscoverFeed) {
        guard let data = try? JSONEncoder().encode(feed) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
