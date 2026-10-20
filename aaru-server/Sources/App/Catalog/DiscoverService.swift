import AaruCore
import Foundation
import Logging

/// A provider-curated public list for Home (DISC-001): trending, airing, this season. The
/// same for every user; nothing here reads a library or a per-user signal, so it is not a
/// recommendations engine. Cases are in display order.
enum DiscoverList: String, Sendable, CaseIterable {
    case tvTrending = "tv_trending"
    case animeSeason = "anime_season"
    case moviesTrending = "movies_trending"
    case tvOnAir = "tv_on_air"
    case animeTrending = "anime_trending"
    case tvNew = "tv_new"
    case moviesInTheaters = "movies_in_theaters"
    case booksTrending = "books_trending"

    func title(now: Date) -> String {
        switch self {
        case .tvTrending: "Trending shows"
        case .animeSeason:
            AnimeSeason.current(now).map { "\($0.season.displayName) \($0.year) anime" } ?? "This season's anime"
        case .moviesTrending: "Trending movies"
        case .tvOnAir: "On the air"
        case .animeTrending: "Trending anime"
        case .tvNew: "New shows"
        case .moviesInTheaters: "In theaters"
        case .booksTrending: "Trending books"
        }
    }
}

/// A provider that serves some of the Discover lists.
protocol DiscoverListing: Sendable {
    var discoverLists: Set<DiscoverList> { get }
    func list(_ list: DiscoverList, now: Date) async throws -> [CatalogHit]
}

/// The anime broadcast season (AniList's `MediaSeason`), by calendar quarter in UTC.
enum AnimeSeason: String, Sendable {
    case winter, spring, summer, fall

    static func current(_ date: Date) -> (season: AnimeSeason, year: Int)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return nil }
        let season: AnimeSeason = switch month {
        case 1 ... 3: .winter
        case 4 ... 6: .spring
        case 7 ... 9: .summer
        default: .fall
        }
        return (season, year)
    }

    var anilist: String {
        rawValue.uppercased()
    }

    var displayName: String {
        rawValue.capitalized
    }
}

struct DiscoverItem: Sendable, Equatable {
    var hit: CatalogHit
    /// The caller's item for this title, when they have it.
    var libraryItemID: LibraryItemID?
}

struct DiscoverRow: Sendable, Equatable {
    var list: DiscoverList
    var title: String
    var items: [DiscoverItem]
}

/// Discover rows (DISC-001): provider lists cached for every user, then marked against the
/// caller's library in one query.
struct DiscoverService: Sendable {
    /// Provider lists move daily at most; six hours keeps Home fresh and providers quiet.
    static let ttl: TimeInterval = 6 * 60 * 60
    /// After a failed fetch, wait this long before asking that provider again.
    static let retryAfter: TimeInterval = 5 * 60
    static let rowLimit = 20

    let stores: Stores
    let sources: [DiscoverList: any DiscoverListing]
    let cache: DiscoverCache
    var now: @Sendable () -> Date = { Date() }

    /// `providers` are the catalog adapters; those that list nothing are skipped.
    init(stores: Stores, providers: [any Sendable], cache: DiscoverCache = DiscoverCache()) {
        self.stores = stores
        self.cache = cache
        var sources: [DiscoverList: any DiscoverListing] = [:]
        for case let provider as any DiscoverListing in providers {
            for list in provider.discoverLists where sources[list] == nil {
                sources[list] = provider
            }
        }
        self.sources = sources
    }

    func rows(userID: UserID) async throws -> [DiscoverRow] {
        let now = now()
        let lists = await withTaskGroup(of: (DiscoverList, [CatalogHit]).self) { group in
            for (list, source) in sources {
                group.addTask {
                    let hits = await cache.hits(list, now: now) { try await source.list(list, now: now) }
                    return (list, hits ?? [])
                }
            }
            var lists: [DiscoverList: [CatalogHit]] = [:]
            for await (list, hits) in group {
                lists[list] = hits
            }
            return lists
        }
        // A poster-less card reads as broken on a poster row.
        let ordered = DiscoverList.allCases.compactMap { list -> (DiscoverList, [CatalogHit])? in
            let hits = (lists[list] ?? []).filter { $0.posterURL != nil }.prefix(Self.rowLimit)
            return hits.isEmpty ? nil : (list, Array(hits))
        }
        let keys = Set(ordered.flatMap { $0.1.flatMap(\.catalogKeys) })
        let owned = try await stores.library.itemIDs(userID: userID, matching: keys)
        return ordered.map { list, hits in
            DiscoverRow(list: list, title: list.title(now: now), items: hits.map { hit in
                DiscoverItem(hit: hit, libraryItemID: hit.catalogKeys.lazy.compactMap { owned[$0] }.first)
            })
        }
    }
}

extension CatalogHit {
    var catalogKeys: [CatalogKey] {
        let candidates: [(CatalogKey.Provider, String?)] = [
            (.tmdb, ids.tmdb), (.anilist, ids.anilist), (.openLibrary, ids.openLibrary),
        ]
        return candidates.compactMap { provider, id in id.map { CatalogKey(type: type, provider: provider, id: $0) } }
    }
}

/// The shared, in-memory list cache. The API runs one replica, so memory is enough; a second
/// replica would only fetch its own copy.
actor DiscoverCache {
    private struct Entry {
        var hits: [CatalogHit]
        var fetchedAt: Date
    }

    private var entries: [DiscoverList: Entry] = [:]
    private var failedAt: [DiscoverList: Date] = [:]
    private var inFlight: [DiscoverList: Task<[CatalogHit], any Error>] = [:]
    private let logger = Logger(label: "aaru-server")

    /// Fresh hits, or a refetch shared by every concurrent caller. A failed refetch serves
    /// the stale copy (nil when there is none) and is not retried for `retryAfter`.
    func hits(
        _ list: DiscoverList,
        now: Date,
        fetch: @escaping @Sendable () async throws -> [CatalogHit]
    ) async -> [CatalogHit]? {
        let cached = entries[list]
        if let cached, now.timeIntervalSince(cached.fetchedAt) < DiscoverService.ttl {
            return cached.hits
        }
        if let failed = failedAt[list], now.timeIntervalSince(failed) < DiscoverService.retryAfter {
            return cached?.hits
        }
        // Unstructured on purpose: one caller disconnecting must not cancel everyone's fetch.
        let task = inFlight[list] ?? Task { try await fetch() }
        inFlight[list] = task
        do {
            let hits = try await task.value
            inFlight[list] = nil
            failedAt[list] = nil
            entries[list] = Entry(hits: hits, fetchedAt: now)
            return hits
        } catch {
            inFlight[list] = nil
            failedAt[list] = now
            logger.warning("Discover list failed", metadata: ["list": "\(list.rawValue)", "error": "\(error)"])
            return cached?.hits
        }
    }
}
