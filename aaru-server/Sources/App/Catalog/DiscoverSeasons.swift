import AaruCore
import Foundation
import Logging

/// A season of the year, by calendar quarter in UTC (DISC-002). It is AniList's `MediaSeason`
/// for anime, and the same quarter for films (by release) and shows (by premiere or airing).
enum SeasonOfYear: String, Sendable, CaseIterable {
    case winter, spring, summer, fall

    static func current(_ date: Date) -> SeasonKey? {
        let parts = SeasonKey.calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return nil }
        return SeasonKey(season: allCases[(month - 1) / 3], year: year)
    }

    var anilist: String {
        rawValue.uppercased()
    }

    var displayName: String {
        rawValue.capitalized
    }

    /// First month of the quarter, 1-based.
    var firstMonth: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) * 3 + 1
    }
}

/// One season of one year, e.g. Fall 2026.
struct SeasonKey: Sendable, Hashable {
    var season: SeasonOfYear
    var year: Int

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    var title: String {
        "\(season.displayName) \(year)"
    }

    var next: SeasonKey {
        season == .fall ? SeasonKey(season: .winter, year: year + 1) : shifted(by: 1)
    }

    var previous: SeasonKey {
        season == .winter ? SeasonKey(season: .fall, year: year - 1) : shifted(by: -1)
    }

    /// `[start, end)`: the first day of the quarter and the first day of the next one.
    var range: (start: Date, end: Date) {
        let start = Self.calendar
            .date(from: DateComponents(year: year, month: season.firstMonth, day: 1)) ?? .distantPast
        let end = Self.calendar.date(byAdding: .month, value: 3, to: start) ?? .distantFuture
        return (start, end)
    }

    /// The first and last day of the season, `YYYY-MM-DD`, as providers' date filters take them.
    var days: (first: String, last: String) {
        let (start, end) = range
        return (Self.day(start), Self.day(end.addingTimeInterval(-24 * 60 * 60)))
    }

    static func day(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func shifted(by offset: Int) -> SeasonKey {
        let all = SeasonOfYear.allCases
        let index = (all.firstIndex(of: season) ?? 0) + offset
        return SeasonKey(season: all[index], year: year)
    }
}

/// What the Seasons view lists for a season.
enum SeasonKind: String, Sendable, CaseIterable {
    /// Anime airing that season (AniList).
    case anime
    /// Shows whose first episode aired that season.
    case showsNew = "shows_new"
    /// Shows that premiered earlier and air episodes that season.
    case showsReturning = "shows_returning"
    /// Films first released that season.
    case movies
}

struct SeasonPage: Sendable, Equatable {
    var hits: [CatalogHit]
    var hasMore: Bool
    /// The provider's count for the whole season, when it gives one.
    var total: Int?
}

/// A provider that lists a season's titles, one page at a time.
protocol SeasonBrowsing: Sendable {
    var seasonKinds: Set<SeasonKind> { get }
    func season(_ key: SeasonKey, kind: SeasonKind, page: Int, now: Date) async throws -> SeasonPage
}

/// One season page, marked against the caller's library. `unavailable` when the provider is
/// down and nothing is cached: clients say so instead of showing an empty season.
struct SeasonResult: Sendable, Equatable {
    var key: SeasonKey
    var kind: SeasonKind
    var page: Int
    var items: [DiscoverItem]
    var hasMore: Bool
    var total: Int?
    var unavailable: Bool
}

extension DiscoverService {
    /// The oldest year the Seasons view goes back to.
    static let firstSeasonYear = 1970
    static let maxSeasonPage = 20

    func season(_ key: SeasonKey, kind: SeasonKind, page: Int, userID: UserID) async throws -> SeasonResult {
        let now = now()
        let latest = (SeasonOfYear.current(now)?.year ?? key.year) + 1
        guard (Self.firstSeasonYear ... latest).contains(key.year) else {
            throw Self.invalid("year", "The year must be between \(Self.firstSeasonYear) and \(latest).")
        }
        guard (1 ... Self.maxSeasonPage).contains(page) else {
            throw Self.invalid("page", "The page must be between 1 and \(Self.maxSeasonPage).")
        }
        guard let source = seasonSources[kind] else {
            return SeasonResult(key: key, kind: kind, page: page, items: [], hasMore: false, unavailable: true)
        }
        // A season that has ended changes little; the current and coming ones move daily.
        let ttl = key.range.end <= now ? Self.pastSeasonTTL : Self.ttl
        let cacheKey = "\(kind.rawValue):\(key.year)-\(key.season.rawValue):\(page)"
        guard let fetched = await seasonCache.page(cacheKey, ttl: ttl, now: now, fetch: {
            try await source.season(key, kind: kind, page: page, now: now)
        }) else {
            return SeasonResult(key: key, kind: kind, page: page, items: [], hasMore: false, unavailable: true)
        }
        let hits = fetched.hits.filter { $0.posterURL != nil }
        return try await SeasonResult(
            key: key, kind: kind, page: page, items: mark(hits, userID: userID),
            hasMore: fetched.hasMore, total: fetched.total, unavailable: false
        )
    }
}

extension DiscoverService {
    static func invalid(_ field: String, _ message: String) -> AppError {
        AppError(status: .unprocessableContent, code: "validation_failed", message: message, details: [field: message])
    }
}

/// Season pages, shared by every user like the Discover lists, bounded so browsing old
/// seasons cannot grow memory without end.
actor SeasonCache {
    static let capacity = 200

    private struct Entry {
        var page: SeasonPage
        var fetchedAt: Date
        var usedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var failedAt: [String: Date] = [:]
    private var inFlight: [String: Task<SeasonPage, any Error>] = [:]
    private let logger = Logger(label: "aaru-server")

    /// A fresh page, or one fetch shared by concurrent callers. A failed fetch serves the stale
    /// copy (nil when there is none) and is not retried for `retryAfter`.
    func page(
        _ key: String,
        ttl: TimeInterval,
        now: Date,
        fetch: @escaping @Sendable () async throws -> SeasonPage
    ) async -> SeasonPage? {
        if var cached = entries[key] {
            cached.usedAt = now
            entries[key] = cached
            if now.timeIntervalSince(cached.fetchedAt) < ttl {
                return cached.page
            }
        }
        let stale = entries[key]?.page
        if let failed = failedAt[key], now.timeIntervalSince(failed) < DiscoverService.retryAfter {
            return stale
        }
        // Unstructured on purpose: one caller disconnecting must not cancel everyone's fetch.
        let task = inFlight[key] ?? Task { try await fetch() }
        inFlight[key] = task
        // Only the first waiter to see its own task settle the cache (actor reentrancy).
        do {
            let page = try await task.value
            guard inFlight[key] == task else { return page }
            inFlight[key] = nil
            failedAt[key] = nil
            store(key, Entry(page: page, fetchedAt: now, usedAt: now))
            return page
        } catch {
            guard inFlight[key] == task else { return entries[key]?.page ?? stale }
            inFlight[key] = nil
            failedAt[key] = now
            logger.warning("Season page failed", metadata: ["key": "\(key)", "error": "\(error)"])
            return stale
        }
    }

    private func store(_ key: String, _ entry: Entry) {
        entries[key] = entry
        while entries.count > Self.capacity, let oldest = entries.min(by: { $0.value.usedAt < $1.value.usedAt }) {
            entries[oldest.key] = nil
        }
    }

    var count: Int {
        entries.count
    }
}
