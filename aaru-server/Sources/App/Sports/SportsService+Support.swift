import Foundation

/// SPT-001 · the sources, cache keys and time and status rules the Sports answers share.
extension SportsService {
    /// Where a followed entity's fixtures come from: a team's own, or a league's.
    func source(_ entity: SportEntity) -> (kind: SportEntityKind, id: String)? {
        switch entity.kind {
        case .league:
            return (.league, entity.id)
        case .team:
            return (.team, entity.id)
        case .player:
            if Self.teamSports.contains(entity.sport), let team = entity.teamID {
                return (.team, team)
            }
            return entity.leagueID.map { (.league, $0) }
        }
    }

    var liveKey: String {
        "live:all"
    }

    func entityKey(_ kind: SportEntityKind, _ id: String) -> String {
        "entity:\(kind.rawValue):\(id)"
    }

    func scheduleKey(_ direction: SportScheduleDirection, _ kind: SportEntityKind, _ id: String) -> String {
        "schedule:\(direction.rawValue):\(kind.rawValue):\(id)"
    }

    func lookup(
        _ kind: SportEntityKind, id: String, listing: any SportsListing, now: Date
    ) async throws -> SportEntity? {
        let found: SportEntity?? = await cache.value(entityKey(kind, id), ttl: TTL.entity, now: now) {
            try await listing.lookup(kind, id: id)
        }
        return found ?? nil
    }

    /// Starts the next and previous schedules of a team or league; returns their keys.
    func primeSchedules(
        _ kind: SportEntityKind, _ id: String, listing: any SportsListing, now: Date
    ) async -> [String] {
        var keys: [String] = []
        for direction in [SportScheduleDirection.next, .previous] {
            let key = scheduleKey(direction, kind, id)
            keys.append(key)
            await cache.prime(key, ttl: TTL.schedule, now: now) { try await listing.schedule(direction, kind, id: id) }
        }
        return keys
    }

    func primeLive(_ listing: any SportsListing, now: Date) async {
        await cache.prime(liveKey, ttl: TTL.live, now: now) { try await listing.live() }
    }

    func liveByID() async -> [String: SportEvent] {
        let live: [SportEvent] = await cache.cached(liveKey) ?? []
        return Dictionary(
            live.filter { $0.status == .live }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Lays the live line over a listed event, and settles statuses the provider left behind:
    /// a past event with a score is finished; a "live" one from half a day ago is too.
    static func normalized(_ event: SportEvent, live: [String: SportEvent], now: Date) -> SportEvent {
        var event = event
        if let line = live[event.id] {
            event.status = line.status
            event.progress = line.progress
            if let score = line.home?.score {
                event.home?.score = score
            }
            if let score = line.away?.score {
                event.away?.score = score
            }
            return event
        }
        let hasScore = event.home?.score != nil || event.away?.score != nil
        let started = event.startsAt.map { $0 < now } ?? false
        if event.status == .scheduled, hasScore, started {
            event.status = .finished
        } else if event.status == .live, let startsAt = event.startsAt,
                  now.timeIntervalSince(startsAt) > 12 * 60 * 60
        {
            event.status = .finished
        }
        if event.status != .live {
            event.progress = nil
        }
        return event
    }

    static func sortKey(_ event: SportEvent) -> String {
        event.startsAt.map { utcDay($0) + ISO8601DateFormatter.string(
            from: $0, timeZone: .gmt, formatOptions: [.withFullTime]
        ) } ?? event.day + "~"
    }

    static func utcDay(_ date: Date) -> String {
        ISO8601DateFormatter.string(from: date, timeZone: .gmt, formatOptions: [.withFullDate])
    }

    /// `YYYY-MM-DD` at 00:00 in the time zone; nil for anything else.
    static func startOfDay(_ date: String, in timeZone: TimeZone) -> Date? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard date.count == 10, parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let day = calendar.date(from: components),
              calendar.component(.day, from: day) == parts[2]
        else { return nil }
        return day
    }

    /// The names TheSportsDB may give a country, lowercased: the English name plus aliases.
    static func countryNames(_ code: String) -> Set<String> {
        var names: Set<String> = []
        if let name = Locale(identifier: "en_US").localizedString(forRegionCode: code) {
            names.insert(name.lowercased())
        }
        switch code {
        case "US": names.formUnion(["usa", "united states", "united states of america"])
        case "GB": names.formUnion(["united kingdom", "uk", "england", "scotland", "wales", "northern ireland"])
        case "IE": names.insert("ireland")
        case "KR": names.formUnion(["south korea", "korea"])
        case "AE": names.insert("uae")
        default: break
        }
        return names
    }
}
