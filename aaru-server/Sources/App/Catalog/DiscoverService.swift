import AaruCore
import Foundation

/// One catalog list Discover shows (CAT-020). Catalog data only: the same for every user.
enum DiscoverFeed: Sendable, Equatable {
    /// TMDB `trending/all/week`, films and shows.
    case trending
    /// TMDB `discover/movie` by popularity, first released in [from, until].
    case upcomingMovies(from: LocalDay, until: LocalDay)
    /// TMDB `discover/tv` by popularity, first aired in [from, until].
    case newShows(from: LocalDay, until: LocalDay)
    /// TMDB `tv/on_the_air`: shows with an episode in the next seven days.
    case onTheAir
    /// AniList's anime of one season, by popularity.
    case animeSeason(AnimeSeason)
}

protocol DiscoverFeeds: Sendable {
    /// The provider's list for `feed`. A feed the provider does not serve is a `ProviderError`.
    func discover(_ feed: DiscoverFeed) async throws -> [CatalogHit]
}

/// A broadcast season as AniList counts it: winter is December to February, so December
/// already belongs to the next year's winter.
struct AnimeSeason: Sendable, Equatable, Hashable {
    enum Name: String, Sendable, CaseIterable {
        case winter, spring, summer, fall
    }

    var name: Name
    var year: Int

    /// The season `now` falls in, by the UTC calendar.
    static func current(now: Date) -> AnimeSeason {
        let day = LocalDay(now, in: .gmt)
        switch day.month {
        case 12: return AnimeSeason(name: .winter, year: day.year + 1)
        case 1 ... 2: return AnimeSeason(name: .winter, year: day.year)
        case 3 ... 5: return AnimeSeason(name: .spring, year: day.year)
        case 6 ... 8: return AnimeSeason(name: .summer, year: day.year)
        default: return AnimeSeason(name: .fall, year: day.year)
        }
    }

    /// The season after this one; fall rolls over into next year's winter.
    var next: AnimeSeason {
        switch name {
        case .winter: AnimeSeason(name: .spring, year: year)
        case .spring: AnimeSeason(name: .summer, year: year)
        case .summer: AnimeSeason(name: .fall, year: year)
        case .fall: AnimeSeason(name: .winter, year: year + 1)
        }
    }
}

/// Discover's sections, as clients name them.
enum DiscoverSectionID: String, Sendable, CaseIterable {
    case trending
    case upcomingMovies = "upcoming_movies"
    case newShows = "new_shows"
    case onTheAir = "on_the_air"
    case animeSeason = "anime_season"
    case animeNextSeason = "anime_next_season"
}

/// One served section. Holds catalog hits and nothing about any user.
struct DiscoverSection: Sendable, Equatable {
    var id: DiscoverSectionID
    /// The anime sections only.
    var animeSeason: AnimeSeason?
    var items: [CatalogHit]
    var fetchedAt: Date
}

/// Discover's sections, cached per process (copies `AppleJWKSCache`'s shape): fresh for `ttl`,
/// served stale for up to `staleIfError` while the provider fails, and fetched once however many
/// requests arrive together. Keys and values are catalog data; no user ever reaches it.
actor DiscoverCache {
    private let ttl: TimeInterval
    private let staleIfError: TimeInterval
    private var entries: [String: DiscoverSection] = [:]
    private var inFlight: [String: Task<DiscoverSection, any Error>] = [:]

    init(ttl: TimeInterval = 6 * 60 * 60, staleIfError: TimeInterval = 24 * 60 * 60) {
        self.ttl = ttl
        self.staleIfError = staleIfError
    }

    /// The cached section for `key`, or `fetch`'s answer. A failed fetch falls back to an entry
    /// at most `staleIfError` old, else throws.
    func section(
        _ key: String,
        now: Date,
        fetch: @escaping @Sendable () async throws -> DiscoverSection
    ) async throws -> DiscoverSection {
        if let cached = entries[key], now.timeIntervalSince(cached.fetchedAt) < ttl {
            return cached
        }
        let task: Task<DiscoverSection, any Error>
        let owner: Bool
        if let running = inFlight[key] {
            task = running
            owner = false
        } else {
            // Unstructured on purpose: one caller disconnecting must not cancel the fetch the
            // others are waiting on.
            task = Task { try await fetch() }
            inFlight[key] = task
            owner = true
        }
        do {
            let fresh = try await task.value
            if owner {
                entries[key] = fresh
                inFlight[key] = nil
            }
            return fresh
        } catch {
            if owner {
                inFlight[key] = nil
            }
            if let stale = entries[key], now.timeIntervalSince(stale.fetchedAt) <= staleIfError {
                return stale
            }
            throw error
        }
    }
}

/// CAT-020: catalog lists to add from without typing. Not a recommendations engine: nothing here
/// reads a library or differs between users.
struct DiscoverService: Sendable {
    /// Upcoming films: released today through this many days ahead.
    static let upcomingDays = 60
    /// New shows: first aired from a week ago to a month ahead.
    static let newShowsDays = -7 ... 30

    let tmdb: any DiscoverFeeds
    let anilist: any DiscoverFeeds
    let cache: DiscoverCache
    var now: @Sendable () -> Date = { Date() }

    /// The requested sections in order. A section whose provider fails (with nothing cached) is
    /// left out; when every requested section fails, the first failure is thrown (502).
    func sections(_ ids: [DiscoverSectionID]) async throws -> [DiscoverSection] {
        let now = now()
        let results = await withTaskGroup(of: (Int, Result<DiscoverSection, any Error>).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    do {
                        return try await (index, .success(section(id, now: now)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var results: [(Int, Result<DiscoverSection, any Error>)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let served = results.compactMap { try? $0.get() }
        if served.isEmpty, !ids.isEmpty {
            try Task.checkCancellation()
            for case let .failure(error) in results {
                throw error
            }
        }
        return served
    }

    private func section(_ id: DiscoverSectionID, now: Date) async throws -> DiscoverSection {
        let source = source(id, now: now)
        let season = source.season
        let key = season.map { "\(id.rawValue):\($0.name.rawValue)-\($0.year)" } ?? id.rawValue
        return try await cache.section(key, now: now) {
            let items = try await source.provider.discover(source.feed)
            return DiscoverSection(id: id, animeSeason: season, items: items, fetchedAt: now)
        }
    }

    /// Which provider serves a section, with what query.
    private struct Source {
        var provider: any DiscoverFeeds
        var feed: DiscoverFeed
        var season: AnimeSeason?
    }

    private func source(_ id: DiscoverSectionID, now: Date) -> Source {
        let today = LocalDay(now, in: .gmt)
        switch id {
        case .trending:
            return Source(provider: tmdb, feed: .trending)
        case .upcomingMovies:
            return Source(
                provider: tmdb, feed: .upcomingMovies(from: today, until: today.adding(days: Self.upcomingDays))
            )
        case .newShows:
            let from = today.adding(days: Self.newShowsDays.lowerBound)
            let until = today.adding(days: Self.newShowsDays.upperBound)
            return Source(provider: tmdb, feed: .newShows(from: from, until: until))
        case .onTheAir:
            return Source(provider: tmdb, feed: .onTheAir)
        case .animeSeason:
            let season = AnimeSeason.current(now: now)
            return Source(provider: anilist, feed: .animeSeason(season), season: season)
        case .animeNextSeason:
            let season = AnimeSeason.current(now: now).next
            return Source(provider: anilist, feed: .animeSeason(season), season: season)
        }
    }
}
