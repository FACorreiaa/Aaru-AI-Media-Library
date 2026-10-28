import AaruCore
import Foundation

/// SPT-002 · what the Sports tab shows: each favorite's live, next and last, one local day of
/// fixtures, and one event with where to watch it.
extension SportsService {
    // MARK: Favorites

    /// Each followed league, team and player with what is live, next and last. Cold answers
    /// get `patience`; the rest come back `pending` and are ready on the next ask.
    func favorites(userID: UserID) async throws -> Favorites {
        let follows = try await stores.sports.follows(userID: userID).map(\.entity)
        guard let listing else {
            return Favorites(
                items: follows.map { Favorite(entity: $0, live: [], next: nil, last: nil, pending: false) },
                unavailable: true
            )
        }
        let now = now()
        let sources = follows.map(source)
        var keys = [liveKey]
        await primeLive(listing, now: now)
        for source in sources.compactMap(\.self) {
            keys += await primeSchedules(source.kind, source.id, listing: listing, now: now)
        }
        await cache.settle(keys, timeout: patience)
        let live = await liveByID()
        var items: [Favorite] = []
        for (entity, source) in zip(follows, sources) {
            await items.append(favorite(entity, source: source, live: live, now: now))
        }
        return Favorites(items: items, unavailable: false)
    }

    private func favorite(
        _ entity: SportEntity, source: (kind: SportEntityKind, id: String)?, live: [String: SportEvent], now: Date
    ) async -> Favorite {
        guard let source else { return Favorite(entity: entity, live: [], next: nil, last: nil, pending: false) }
        let nextKey = scheduleKey(.next, source.kind, source.id)
        let previousKey = scheduleKey(.previous, source.kind, source.id)
        let upcoming: [SportEvent] = await cache.cached(nextKey) ?? []
        let past: [SportEvent] = await cache.cached(previousKey) ?? []
        let hasNext = await cache.has(nextKey)
        let hasPrevious = await cache.has(previousKey)
        let listed = (upcoming + past).map { Self.normalized($0, live: live, now: now) }
        let concerns: (SportEvent) -> Bool = { event in
            source.kind == .team ? event.involves(team: source.id) : event.leagueID == source.id
        }
        // The listed copy carries badges and the round; the feed adds games the list missed.
        var playing = listed.filter { $0.status == .live && concerns($0) }
        let listedIDs = Set(listed.map(\.id))
        playing += live.values.filter { concerns($0) && !listedIDs.contains($0.id) }
        let next = listed.filter { $0.status == .scheduled && $0.startsAt.map { $0 > now } ?? true }
            .min { Self.sortKey($0) < Self.sortKey($1) }
        let last = listed.filter { $0.status == .finished }.max { Self.sortKey($0) < Self.sortKey($1) }
        return Favorite(
            entity: entity, live: playing.sorted { Self.sortKey($0) < Self.sortKey($1) }, next: next, last: last,
            pending: !hasNext || !hasPrevious
        )
    }

    // MARK: Schedule

    /// One local day (`date` in `timeZone`): the events of followed leagues and of the leagues
    /// of followed teams and players, plus any followed team's game that day in another
    /// competition. Grouped by league, favorites first.
    func schedule(userID: UserID, date: String, timeZone: TimeZone) async throws -> Schedule {
        guard let start = Self.startOfDay(date, in: timeZone) else { throw AppError.badRequest() }
        let end = start.addingTimeInterval(24 * 60 * 60)
        let follows = try await stores.sports.follows(userID: userID).map(\.entity)
        guard let listing else { return Schedule(date: date, groups: [], pending: false, unavailable: true) }
        let now = now()
        let days = Set([Self.utcDay(start), Self.utcDay(end.addingTimeInterval(-1))]).sorted()
        let (events, pending) = await fixtures(of: follows, days: days, listing: listing, now: now)
        let live = await liveByID()
        var seen = Set<String>()
        let today = events.map { Self.normalized($0, live: live, now: now) }.filter { event in
            guard seen.insert(event.id).inserted else { return false }
            if let startsAt = event.startsAt {
                return startsAt >= start && startsAt < end
            }
            return event.day == date
        }
        let favoriteTeams = Set(follows.compactMap { $0.kind == .team ? $0.id : $0.teamID })
        return Schedule(
            date: date, groups: Self.grouped(today, favoriteTeams: favoriteTeams), pending: pending,
            unavailable: false
        )
    }

    /// The followed leagues' events on these UTC days and the followed teams' own fixtures,
    /// and whether some are still being fetched.
    private func fixtures(
        of follows: [SportEntity], days: [String], listing: any SportsListing, now: Date
    ) async -> (events: [SportEvent], pending: Bool) {
        var leagues: [String] = []
        for id in follows.compactMap(\.leagueID) where !leagues.contains(id) {
            leagues.append(id)
        }
        var keys: [String] = []
        await primeLive(listing, now: now)
        for league in leagues.prefix(Self.maxScheduleLeagues) {
            for day in days {
                let key = "day:\(league):\(day)"
                keys.append(key)
                await cache.prime(key, ttl: TTL.day, now: now) { try await listing.events(day: day, leagueID: league) }
            }
        }
        for team in follows.compactMap(source) where team.kind == .team {
            keys += await primeSchedules(.team, team.id, listing: listing, now: now)
        }
        await cache.settle(keys + [liveKey], timeout: patience)
        var pending = false
        var events: [SportEvent] = []
        for key in keys {
            guard let found: [SportEvent] = await cache.cached(key) else {
                pending = true
                continue
            }
            events += found
        }
        return (events, pending)
    }

    /// Events by league, each sorted by start; leagues with a favorite first, then by name.
    static func grouped(_ events: [SportEvent], favoriteTeams: Set<String>) -> [ScheduleGroup] {
        var groups: [String: ScheduleGroup] = [:]
        for event in events {
            let key = event.leagueID ?? event.league ?? event.sport
            var group = groups[key] ?? ScheduleGroup(
                leagueID: event.leagueID, league: event.league ?? event.sport, sport: event.sport,
                badgeURL: event.leagueBadgeURL, events: []
            )
            group.badgeURL = group.badgeURL ?? event.leagueBadgeURL
            let favorite = favoriteTeams.contains { event.involves(team: $0) }
            group.events.append(ScheduledEvent(event: event, isFavorite: favorite))
            groups[key] = group
        }
        return groups.values.map { group in
            var group = group
            group.events.sort { sortKey($0.event) < sortKey($1.event) }
            return group
        }.sorted { lhs, rhs in
            let lhsFavorite = lhs.events.contains(where: \.isFavorite)
            let rhsFavorite = rhs.events.contains(where: \.isFavorite)
            if lhsFavorite != rhsFavorite {
                return lhsFavorite
            }
            return lhs.league.localizedCaseInsensitiveCompare(rhs.league) == .orderedAscending
        }
    }

    // MARK: Event

    /// One event with its live line and where to watch it, split by the user's country.
    func event(id: String, userID: UserID) async throws -> EventDetail? {
        guard let listing else { throw SportsOff() }
        let now = now()
        await primeLive(listing, now: now)
        async let found = cache.value("event:\(id)", ttl: TTL.event, now: now) { try await listing.event(id: id) }
        async let channels = cache.value("tv:\(id)", ttl: TTL.broadcasts, now: now) {
            try await listing.broadcasts(eventID: id)
        }
        async let country = stores.sports.watchCountry(userID: userID)
        async let follows = stores.sports.follows(userID: userID).map(\.entity)
        guard let event = await found ?? nil else { return nil }
        await cache.settle([liveKey], timeout: patience)
        let live = await liveByID()
        let code = try await country
        let favoriteTeams = try await Set(follows.compactMap { $0.kind == .team ? $0.id : $0.teamID })
        let names = code.map(Self.countryNames) ?? []
        let all = await channels ?? []
        let mine = all.filter { $0.country.map { names.contains($0.lowercased()) } ?? false }
        return EventDetail(
            event: Self.normalized(event, live: live, now: now),
            isFavorite: favoriteTeams.contains { event.involves(team: $0) },
            inYourCountry: mine,
            elsewhere: all.filter { !mine.contains($0) }.sorted {
                ($0.country ?? "~", $0.channel) < ($1.country ?? "~", $1.channel)
            },
            watchCountryCode: code
        )
    }

    /// One event with its live line, for anyone (SHR-002): no watch country, no follows, no user.
    /// It shares `event(id:userID:)`'s cache entry, so a busy share link costs one provider call.
    func publicEvent(id: String) async throws -> SportEvent? {
        guard let listing else { throw SportsOff() }
        let now = now()
        await primeLive(listing, now: now)
        let found = await cache.value("event:\(id)", ttl: TTL.event, now: now) { try await listing.event(id: id) }
        guard let event = found ?? nil else { return nil }
        await cache.settle([liveKey], timeout: patience)
        return await Self.normalized(event, live: liveByID(), now: now)
    }
}
