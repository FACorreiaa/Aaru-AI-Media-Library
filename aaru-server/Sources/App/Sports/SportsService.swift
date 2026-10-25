import AaruCore
import Foundation

/// Sports are off on this server: no provider key.
struct SportsOff: Error {}
/// The provider does not know that league, team or player.
struct UnknownSportEntity: Error {}
/// The user follows `SportsService.followLimit` already.
struct TooManySportFollows: Error {}

/// SPT-001…002 · the Sports tab: what the user follows, their fixtures, near-live scores,
/// results and where to watch. Lives only in Sports: it never writes the library, the journal,
/// points or activity, and no agent tool reads it. Off (every answer `unavailable`) without a
/// provider.
struct SportsService: Sendable {
    static let followLimit = 100
    /// Leagues fetched for one day of the schedule.
    static let maxScheduleLeagues = 30

    enum TTL {
        static let live: TimeInterval = 90
        static let schedule: TimeInterval = 30 * 60
        static let day: TimeInterval = 15 * 60
        static let event: TimeInterval = 5 * 60
        static let entity: TimeInterval = 24 * 60 * 60
        static let broadcasts: TimeInterval = 6 * 60 * 60
    }

    /// Sports where a player's team plays the fixtures; elsewhere (fighting, tennis, motorsport)
    /// a player's events are their league's or promotion's.
    static let teamSports: Set<String> = [
        "Soccer", "Basketball", "American Football", "Ice Hockey", "Baseball", "Rugby", "Australian Football",
        "Handball", "Volleyball", "Cricket", "Field Hockey", "Netball", "Water Polo",
    ]

    /// The first-run picks (owner, 2026-10-24), by TheSportsDB league id.
    static let suggested: [SportEntity] = [
        ("4328", "English Premier League", "Soccer"),
        ("4335", "Spanish La Liga", "Soccer"),
        ("4332", "Italian Serie A", "Soccer"),
        ("4331", "German Bundesliga", "Soccer"),
        ("4334", "French Ligue 1", "Soccer"),
        ("4344", "Portuguese Primeira Liga", "Soccer"),
        ("4480", "UEFA Champions League", "Soccer"),
        ("4387", "NBA", "Basketball"),
        ("4391", "NFL", "American Football"),
        ("4443", "UFC", "Fighting"),
        ("4444", "WWE", "Fighting"),
    ].map { SportEntity(kind: .league, id: $0.0, name: $0.1, sport: $0.2, leagueID: $0.0) }

    struct Favorite: Sendable, Equatable {
        var entity: SportEntity
        var live: [SportEvent]
        var next: SportEvent?
        var last: SportEvent?
        /// Still being fetched; ask again in a few seconds.
        var pending: Bool
    }

    struct Favorites: Sendable, Equatable {
        var items: [Favorite]
        var unavailable: Bool
    }

    struct ScheduledEvent: Sendable, Equatable {
        var event: SportEvent
        /// A followed team (or player's team) plays in it.
        var isFavorite: Bool
    }

    struct ScheduleGroup: Sendable, Equatable {
        var leagueID: String?
        var league: String
        var sport: String
        var badgeURL: URL?
        var events: [ScheduledEvent]
    }

    struct Schedule: Sendable, Equatable {
        var date: String
        var groups: [ScheduleGroup]
        var pending: Bool
        var unavailable: Bool
    }

    struct EventDetail: Sendable, Equatable {
        var event: SportEvent
        var isFavorite: Bool
        var inYourCountry: [SportBroadcast]
        var elsewhere: [SportBroadcast]
        var watchCountryCode: String?
    }

    let stores: Stores
    let listing: (any SportsListing)?
    let cache = SportsCache()
    var now: @Sendable () -> Date = { Date() }
    /// How long a request waits for cold answers before returning what it has, `pending`.
    var patience: Duration = .seconds(3)

    var isAvailable: Bool {
        listing != nil
    }

    // MARK: Catalog

    /// The first-run picks, with their badges once known.
    func suggestions() async -> [SportEntity] {
        guard let listing else { return Self.suggested }
        let now = now()
        let keys = Self.suggested.map { entityKey(.league, $0.id) }
        for pick in Self.suggested {
            await cache.prime(entityKey(.league, pick.id), ttl: TTL.entity, now: now) {
                try await listing.lookup(.league, id: pick.id)
            }
        }
        await cache.settle(keys, timeout: patience)
        var picks: [SportEntity] = []
        for pick in Self.suggested {
            let found: SportEntity?? = await cache.cached(entityKey(.league, pick.id))
            var entity = pick
            entity.badgeURL = found??.badgeURL
            picks.append(entity)
        }
        return picks
    }

    /// Leagues, teams and players by name; `kind` nil searches all three.
    func search(_ query: String, kind: SportEntityKind?) async throws -> [SportEntity] {
        guard let listing else { throw SportsOff() }
        let slug = query.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let kinds = kind.map { [$0] } ?? [.league, .team, .player]
        let now = now()
        return await withTaskGroup(of: (Int, [SportEntity]).self) { group in
            for (index, kind) in kinds.enumerated() {
                group.addTask {
                    let found = await cache.value("search:\(kind.rawValue):\(slug)", ttl: TTL.entity, now: now) {
                        try await listing.search(kind, slug)
                    }
                    return (index, found ?? [])
                }
            }
            var byKind: [(Int, [SportEntity])] = []
            for await answer in group {
                byKind.append(answer)
            }
            return byKind.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    // MARK: Follows

    func follows(userID: UserID) async throws -> [SportEntity] {
        try await stores.sports.follows(userID: userID).map(\.entity)
    }

    /// Follows by the provider's id, after looking it up: the name, sport, badge and (for a
    /// team or player) league are kept so the list renders while the provider is down.
    func follow(_ kind: SportEntityKind, id: String, userID: UserID) async throws -> SportEntity {
        guard let listing else { throw SportsOff() }
        let now = now()
        guard var entity = try await lookup(kind, id: id, listing: listing, now: now) else {
            throw UnknownSportEntity()
        }
        if kind == .player, let teamID = entity.teamID {
            // A player's fixtures come from their team, or (a fighter) the team's league.
            let team = try await lookup(.team, id: teamID, listing: listing, now: now)
            entity.leagueID = team?.leagueID
            entity.teamName = entity.teamName ?? team?.name
        }
        guard try await stores.sports.follow(entity, userID: userID, limit: Self.followLimit, now: now) else {
            throw TooManySportFollows()
        }
        return entity
    }

    func unfollow(_ kind: SportEntityKind, id: String, userID: UserID) async throws {
        try await stores.sports.unfollow(kind: kind, id: id, userID: userID)
    }

    func watchCountry(userID: UserID) async throws -> String? {
        try await stores.sports.watchCountry(userID: userID)
    }

    func saveWatchCountry(_ code: String?, userID: UserID) async throws {
        try await stores.sports.saveWatchCountry(code, userID: userID, now: now())
    }
}
