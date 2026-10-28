import AaruCore
import Foundation
import Logging

/// Neither a one-off position nor a saved "Concerts near" city: the client asks for one.
struct NoConcertPlace: Error {}

/// MUS-003 · concerts near a place and for the artists in the user's library. Provider lists,
/// the same for everyone at a place, linked out to buy; never a recommendation. Off (every
/// answer `unavailable`) when no concert provider is configured.
struct ConcertService: Sendable {
    static let radii: Set<Int> = [25, 50, 100]
    /// Ticketmaster takes many performer ids in one call; 20 keeps the URL short.
    static let artistsPerCall = 20
    /// The most matched artists asked about per request, most-shelved first.
    static let maxArtists = 60
    static let maxArtistConcerts = 50
    /// Performers offered for one typed name.
    static let maxPerformers = 8

    struct Nearby: Sendable, Equatable {
        /// The saved city, when it was the centre.
        var place: ConcertPlace?
        var radiusKm: Int
        var page: Int
        var results: ConcertResults
        var unavailable: Bool
    }

    struct Searched: Sendable, Equatable {
        /// The name as searched, trimmed.
        var query: String
        /// The performer picked, when the search was by one.
        var performerID: String?
        var scope: ConcertSearchScope
        /// The saved city, when it was the centre or the distances are from it.
        var place: ConcertPlace?
        /// The radius, for `near`.
        var radiusKm: Int?
        var page: Int
        var results: ConcertResults
        var unavailable: Bool
    }

    struct ForArtists: Sendable, Equatable {
        var concerts: [Concert]
        /// Library artists the provider knows.
        var matched: Int
        /// Library artists not looked up yet; they appear within the hour.
        var pending: Int
        var unavailable: Bool
    }

    let stores: Stores
    let listing: (any ConcertListing)?
    let places: (any PlaceSearching)?
    let cache = ConcertCache<ConcertResults>()
    let performerCache = ConcertCache<[ConcertAttraction]>()
    /// One concert by id for share links (SHR-002); nil inside means the provider has no such event.
    let eventCache = ConcertCache<Concert?>()
    var now: @Sendable () -> Date = { Date() }

    var isAvailable: Bool {
        listing != nil
    }

    /// One concert by provider id through the shared cache (SHR-002). Nil when concerts are off,
    /// the provider fails or is over budget with nothing cached, or the event is gone. Never throws.
    func concert(id: String) async -> Concert? {
        guard let listing else { return nil }
        let found = await eventCache.value("event:\(id)", now: now()) { try await listing.event(id: id) }
        return found ?? nil
    }

    /// Concerts around `point` (already rounded), or around the saved city when it is nil.
    func near(userID: UserID, point: GeoPoint?, radiusKm: Int, page: Int) async throws -> Nearby {
        guard let listing else {
            return Nearby(
                place: nil, radiusKm: radiusKm, page: page, results: .init(concerts: [], hasMore: false),
                unavailable: true
            )
        }
        let place = point == nil ? try await stores.concerts.place(userID: userID) : nil
        guard let center = point ?? place?.point else { throw NoConcertPlace() }
        let now = now()
        // The geohash cell, not the point, keys the cache: everyone in the same ~5 km cell shares it.
        let results = await cache.value("near:\(center.geohash()):\(radiusKm):\(page)", now: now) {
            try await listing.near(center, radiusKm: radiusKm, page: page, from: now)
        }
        return Nearby(
            place: place, radiusKm: radiusKm, page: page,
            results: results ?? ConcertResults(concerts: [], hasMore: false), unavailable: results == nil
        )
    }

    /// Concerts matching an artist's name (MUS-010). `near` searches around `point` (already
    /// rounded) or the saved city; `anywhere` sends the provider the name alone and works out
    /// each venue's distance from the point or saved city here, after the shared cache.
    func search(_ search: ConcertSearch, userID: UserID, point: GeoPoint?) async throws -> Searched {
        let (query, scope, page) = (search.query, search.scope, search.page)
        let radius = scope == .near ? search.radiusKm : nil
        guard let listing else {
            return Searched(
                query: query, performerID: search.performerID, scope: scope, place: nil, radiusKm: radius,
                page: page, results: .init(concerts: [], hasMore: false), unavailable: true
            )
        }
        let place = point == nil ? try await stores.concerts.place(userID: userID) : nil
        let center = point ?? place?.point
        let area: (point: GeoPoint, radiusKm: Int)?
        switch scope {
        case .near:
            guard let center else { throw NoConcertPlace() }
            area = (center, search.radiusKm)
        case .anywhere:
            area = nil
        }
        let now = now()
        // Keyed by the performer, or the name as everyone types it, and the cell; never by who asked.
        let match: ConcertMatch = search.performerID.map { .performer(id: $0) } ?? .keyword(query)
        let matched = search.performerID.map { "performer=\($0)" } ?? query.lowercased()
        let cell = area.map { $0.point.geohash() } ?? "*"
        let key = "search:\(matched):\(cell):\(radius.map(String.init) ?? "*"):\(page)"
        let found = await cache.value(key, now: now) {
            try await listing.search(match, near: area, page: page, from: now)
        }
        var results = found ?? ConcertResults(concerts: [], hasMore: false)
        if scope == .anywhere {
            results.concerts = results.concerts.map { concert in
                var concert = concert
                concert.distanceKm = center.flatMap { center in concert.venuePoint.map(center.distanceKm) }
                return concert
            }
        }
        return Searched(
            query: query, performerID: search.performerID, scope: scope, place: place, radiusKm: radius, page: page,
            results: results, unavailable: found == nil
        )
    }

    /// Performers whose name matches what the user typed, for picking one before a search
    /// (MUS-010): the provider's own list, cached by the lowercased name. Nil when concerts are off
    /// or the provider did not answer.
    func performers(matching query: String) async -> [ConcertAttraction]? {
        guard let listing else { return nil }
        let found = await performerCache.value("performers:\(query.lowercased())", now: now()) {
            try await listing.attractions(named: query)
        }
        guard let found else { return nil }
        var seen: Set<String> = []
        return Array(found.filter { seen.insert($0.id).inserted }.prefix(Self.maxPerformers))
    }

    /// Upcoming concerts by the artists of the user's albums, matched by MusicBrainz id.
    func forLibrary(userID: UserID) async throws -> ForArtists {
        let artists = try await stores.concerts.libraryArtists(userID: userID)
        var ids: [String] = []
        for id in artists.compactMap(\.performerID) where !ids.contains(id) {
            ids.append(id)
        }
        let pending = artists.count { !$0.checked }
        guard let listing else { return ForArtists(concerts: [], matched: 0, pending: 0, unavailable: true) }
        let now = now()
        let chunks = stride(from: 0, to: min(ids.count, Self.maxArtists), by: Self.artistsPerCall).map {
            Array(ids[$0 ..< min($0 + Self.artistsPerCall, ids.count, Self.maxArtists)]).sorted()
        }
        var concerts: [Concert] = []
        var failed = 0
        for chunk in chunks {
            let found = await cache.value("artists:\(chunk.joined(separator: ","))", now: now) {
                try await ConcertResults(concerts: listing.performing(chunk, from: now), hasMore: false)
            }
            guard let found else {
                failed += 1
                continue
            }
            concerts += found.concerts.filter { concert in !concerts.contains { $0.id == concert.id } }
        }
        concerts.sort { ($0.localDate, $0.localTime ?? "") < ($1.localDate, $1.localTime ?? "") }
        return ForArtists(
            concerts: Array(concerts.prefix(Self.maxArtistConcerts)), matched: ids.count, pending: pending,
            unavailable: !chunks.isEmpty && failed == chunks.count
        )
    }

    /// Cities matching what the user typed, for the "Concerts near" picker.
    func places(matching query: String) async throws -> [ConcertPlace] {
        guard let places else { return [] }
        return try await places.places(matching: query)
    }
}

/// Concert answers by key for six hours (Ticketmaster's terms allow short caching). A failed
/// refresh serves the stale copy and is not retried for five minutes. Bounded: the oldest
/// entries go first.
actor ConcertCache<Value: Sendable> {
    // Computed: a generic type cannot hold stored statics.
    static var ttl: TimeInterval {
        6 * 60 * 60
    }

    static var retryAfter: TimeInterval {
        5 * 60
    }

    static var maxEntries: Int {
        500
    }

    private struct Entry {
        var value: Value
        var fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var failedAt: [String: Date] = [:]
    private var inFlight: [String: Task<Value, any Error>] = [:]
    private let logger = Logger(label: "aaru-server")

    func value(
        _ key: String,
        now: Date,
        fetch: @escaping @Sendable () async throws -> Value
    ) async -> Value? {
        let cached = entries[key]
        if let cached, now.timeIntervalSince(cached.fetchedAt) < Self.ttl {
            return cached.value
        }
        if let failed = failedAt[key], now.timeIntervalSince(failed) < Self.retryAfter {
            return cached?.value
        }
        // Unstructured on purpose: one caller disconnecting must not cancel everyone's fetch.
        let task = inFlight[key] ?? Task { try await fetch() }
        inFlight[key] = task
        // Only the first waiter to see its own task settle the cache (actor reentrancy).
        do {
            let value = try await task.value
            guard inFlight[key] == task else { return value }
            inFlight[key] = nil
            failedAt[key] = nil
            entries[key] = Entry(value: value, fetchedAt: now)
            trim(now: now)
            return value
        } catch {
            guard inFlight[key] == task else { return entries[key]?.value ?? cached?.value }
            inFlight[key] = nil
            failedAt[key] = now
            // The key holds a location cell; the log names only the kind of query.
            logger.warning("Concert list failed", metadata: [
                "query": "\(key.prefix { $0 != ":" })", "error": "\(error)",
            ])
            return cached?.value
        }
    }

    private func trim(now: Date) {
        failedAt = failedAt.filter { now.timeIntervalSince($0.value) < Self.retryAfter }
        guard entries.count > Self.maxEntries else { return }
        let oldest = entries.sorted { $0.value.fetchedAt < $1.value.fetchedAt }.prefix(entries.count - Self.maxEntries)
        for (key, _) in oldest {
            entries[key] = nil
        }
    }
}
