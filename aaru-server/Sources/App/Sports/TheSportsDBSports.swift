import Foundation

/// SPT-001 · TheSportsDB: leagues, teams, players, schedules, livescores and TV listings for
/// every sport Aaru shows (football, basketball, American football, UFC, WWE…). Premium key,
/// 100 requests a minute. v2 sends the key in `X-API-KEY`; the two v1 calls v2 lacks (a
/// league's day, an event's TV) carry it in the path. Images are referenced, never hosted.
struct TheSportsDBSports: SportsListing {
    static let v2URL = URL(string: "https://www.thesportsdb.com/api/v2/json")!
    static let v1URL = URL(string: "https://www.thesportsdb.com/api/v1/json")!

    let client: ProviderClient
    let apiKey: String

    func search(_ kind: SportEntityKind, _ query: String) async throws -> [SportEntity] {
        let slug = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: "_")
        guard !slug.isEmpty else { return [] }
        let page = try await v2(Rows<WireEntity>.self, "search/\(kind.rawValue)/\(slug)")
        return page.rows("search").compactMap { $0.entity(kind) }
    }

    func lookup(_ kind: SportEntityKind, id: String) async throws -> SportEntity? {
        do {
            return try await v2(Rows<WireEntity>.self, "lookup/\(kind.rawValue)/\(id)").rows("lookup").first?
                .entity(kind)
        } catch let error as ProviderError where error.kind == .notFound {
            return nil
        }
    }

    func schedule(
        _ direction: SportScheduleDirection, _ kind: SportEntityKind, id: String
    ) async throws -> [SportEvent] {
        guard kind != .player else { return [] }
        return try await v2(Rows<WireEvent>.self, "schedule/\(direction.rawValue)/\(kind.rawValue)/\(id)")
            .rows("schedule").compactMap(\.event)
    }

    func events(day: String, leagueID: String) async throws -> [SportEvent] {
        try await v1(Rows<WireEvent>.self, "eventsday.php", ["d": day, "l": leagueID]).rows("events")
            .compactMap(\.event)
    }

    func event(id: String) async throws -> SportEvent? {
        do {
            return try await v2(Rows<WireEvent>.self, "lookup/event/\(id)").rows("lookup").first?.event
        } catch let error as ProviderError where error.kind == .notFound {
            return nil
        }
    }

    func live() async throws -> [SportEvent] {
        try await v2(Rows<WireLiveScore>.self, "livescore/all").rows("livescore").compactMap(\.event)
    }

    func broadcasts(eventID: String) async throws -> [SportBroadcast] {
        try await v1(Rows<WireBroadcast>.self, "lookuptv.php", ["id": eventID]).rows("tvevent")
            .compactMap(\.broadcast)
    }

    /// The provider's free text, read loosely: "NS", "Not Started", "FT", "Match Finished",
    /// "AET", "PST", "CANC", "1H", "HT", "Q3"… Anything unknown with a clock is live.
    static func status(_ text: String?, postponed: String? = nil) -> SportEventStatus {
        if postponed?.lowercased() == "yes" {
            return .postponed
        }
        let value = (text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        switch value {
        case "", "ns", "not started", "tbd", "time to be defined", "scheduled":
            return .scheduled
        case "ft", "aet", "pen", "ap", "aot", "ft/ot", "final", "awarded", "awd", "wo":
            return .finished
        case "pst", "postponed", "delayed", "susp", "suspended", "int", "interrupted":
            return .postponed
        case "canc", "cancelled", "canceled", "abd", "abandoned":
            return .cancelled
        default:
            if value.contains("finish") || value.hasPrefix("final") || value.hasPrefix("after") {
                return .finished
            }
            if value.contains("postpon") {
                return .postponed
            }
            if value.contains("cancel") || value.contains("abandon") {
                return .cancelled
            }
            if value.contains("not started") {
                return .scheduled
            }
            return .live
        }
    }

    /// `2026-10-24T14:00:00` (UTC, no zone) or with an offset; else the day and time fields.
    static func instant(_ timestamp: String?, day: String?, time: String?) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let timestamp, !timestamp.isEmpty {
            if let date = formatter.date(from: timestamp) {
                return date
            }
            if let date = formatter.date(from: timestamp + "Z") {
                return date
            }
        }
        guard let day, day.count == 10, let time, time.count >= 5, !time.hasPrefix("00:00:00+") else { return nil }
        let clock = time.count >= 8 ? String(time.prefix(8)) : String(time.prefix(5)) + ":00"
        return formatter.date(from: "\(day)T\(clock)Z")
    }

    private func v2<T: Decodable>(_: T.Type, _ path: String) async throws -> T {
        try await client.decode(T.self, OutboundRequest(
            url: Self.v2URL.appendingPathComponent(path),
            headers: [("Accept", "application/json"), ("X-API-KEY", apiKey)]
        ))
    }

    private func v1<T: Decodable>(_: T.Type, _ file: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(
            url: Self.v1URL.appendingPathComponent(apiKey).appendingPathComponent(file),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw ProviderError(provider: "thesportsdb", kind: .malformed) }
        return try await client.decode(T.self, OutboundRequest(url: url, headers: [("Accept", "application/json")]))
    }
}

// MARK: - TheSportsDB wire shapes (private to this adapter)

/// Every answer is `{"<key>": [rows]}`, where the key varies by call and an empty answer is
/// `null` or a sentence ("No data found").
private struct Rows<Row: Decodable>: Decodable {
    private let byKey: [String: [Row]]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var byKey: [String: [Row]] = [:]
        for key in container.allKeys {
            byKey[key.stringValue] = try? container.decode([Lenient<Row>].self, forKey: key).compactMap(\.value)
        }
        self.byKey = byKey
    }

    func rows(_ key: String) -> [Row] {
        byKey[key] ?? []
    }
}

/// One row that may not decode; a bad row is skipped, not the whole answer.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// A field TheSportsDB sends as a string, a number or null, depending on the row.
private struct Loose: Decodable {
    let text: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            text = nil
        } else if let string = try? container.decode(String.self) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            text = trimmed.isEmpty ? nil : trimmed
        } else if let int = try? container.decode(Int.self) {
            text = String(int)
        } else if let double = try? container.decode(Double.self) {
            text = String(double)
        } else {
            text = nil
        }
    }

    var int: Int? {
        text.flatMap { Int($0) ?? Double($0).map { Int($0) } }
    }

    var url: URL? {
        text.flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil }
    }
}

private struct WireEntity: Decodable {
    let idLeague: Loose?
    let strLeague: Loose?
    let idTeam: Loose?
    let strTeam: Loose?
    let idPlayer: Loose?
    let strPlayer: Loose?
    let strSport: Loose?
    let strBadge: Loose?
    let strLogo: Loose?
    let strThumb: Loose?
    let strCutout: Loose?
    let strCountry: Loose?
    let strNationality: Loose?

    func entity(_ kind: SportEntityKind) -> SportEntity? {
        let sport = strSport?.text ?? ""
        switch kind {
        case .league:
            guard let id = idLeague?.text, let name = strLeague?.text else { return nil }
            return SportEntity(
                kind: .league, id: id, name: name, sport: sport, badgeURL: strBadge?.url ?? strLogo?.url,
                country: strCountry?.text, leagueID: id
            )
        case .team:
            guard let id = idTeam?.text, let name = strTeam?.text else { return nil }
            return SportEntity(
                kind: .team, id: id, name: name, sport: sport, badgeURL: strBadge?.url ?? strLogo?.url,
                country: strCountry?.text, leagueID: idLeague?.text
            )
        case .player:
            guard let id = idPlayer?.text, let name = strPlayer?.text else { return nil }
            return SportEntity(
                kind: .player, id: id, name: name, sport: sport, badgeURL: strCutout?.url ?? strThumb?.url,
                country: strNationality?.text, teamID: idTeam?.text, teamName: strTeam?.text
            )
        }
    }
}

private struct WireEvent: Decodable {
    let idEvent: Loose?
    let strEvent: Loose?
    let strSport: Loose?
    let idLeague: Loose?
    let strLeague: Loose?
    let strLeagueBadge: Loose?
    let idHomeTeam: Loose?
    let strHomeTeam: Loose?
    let strHomeTeamBadge: Loose?
    let intHomeScore: Loose?
    let idAwayTeam: Loose?
    let strAwayTeam: Loose?
    let strAwayTeamBadge: Loose?
    let intAwayScore: Loose?
    let strTimestamp: Loose?
    let dateEvent: Loose?
    let strTime: Loose?
    let strStatus: Loose?
    let strProgress: Loose?
    let strPostponed: Loose?
    let strVenue: Loose?
    let intRound: Loose?
    let strThumb: Loose?
    let strPoster: Loose?

    var event: SportEvent? {
        guard let id = idEvent?.text, let name = strEvent?.text else { return nil }
        let startsAt = TheSportsDBSports.instant(strTimestamp?.text, day: dateEvent?.text, time: strTime?.text)
        guard let day = dateEvent?.text.map({ String($0.prefix(10)) }) ?? startsAt.map(Self.utcDay) else { return nil }
        let home = strHomeTeam?.text.map {
            SportSide(id: idHomeTeam?.text, name: $0, badgeURL: strHomeTeamBadge?.url, score: intHomeScore?.int)
        }
        let away = strAwayTeam?.text.map {
            SportSide(id: idAwayTeam?.text, name: $0, badgeURL: strAwayTeamBadge?.url, score: intAwayScore?.int)
        }
        let round = intRound?.int.flatMap { $0 > 0 ? "Round \($0)" : nil }
        return SportEvent(
            id: id, sport: strSport?.text ?? "", name: name, leagueID: idLeague?.text, league: strLeague?.text,
            leagueBadgeURL: strLeagueBadge?.url, home: home, away: away, startsAt: startsAt, day: day,
            status: TheSportsDBSports.status(strStatus?.text, postponed: strPostponed?.text),
            progress: strProgress?.text, venue: strVenue?.text, round: round,
            imageURL: strThumb?.url ?? strPoster?.url
        )
    }

    static func utcDay(_ date: Date) -> String {
        ISO8601DateFormatter.string(from: date, timeZone: .gmt, formatOptions: [.withFullDate])
    }
}

private struct WireLiveScore: Decodable {
    let idEvent: Loose?
    let strSport: Loose?
    let idLeague: Loose?
    let strLeague: Loose?
    let idHomeTeam: Loose?
    let strHomeTeam: Loose?
    let strHomeTeamBadge: Loose?
    let intHomeScore: Loose?
    let idAwayTeam: Loose?
    let strAwayTeam: Loose?
    let strAwayTeamBadge: Loose?
    let intAwayScore: Loose?
    let strStatus: Loose?
    let strProgress: Loose?
    let strEventTime: Loose?
    let dateEvent: Loose?

    var event: SportEvent? {
        guard let id = idEvent?.text, let home = strHomeTeam?.text, let away = strAwayTeam?.text,
              let day = dateEvent?.text.map({ String($0.prefix(10)) })
        else { return nil }
        // The feed puts the clock in `strProgress` and sometimes leaves `strStatus` blank.
        return SportEvent(
            id: id, sport: strSport?.text ?? "", name: "\(home) vs \(away)", leagueID: idLeague?.text,
            league: strLeague?.text, leagueBadgeURL: nil,
            home: SportSide(
                id: idHomeTeam?.text,
                name: home,
                badgeURL: strHomeTeamBadge?.url,
                score: intHomeScore?.int
            ),
            away: SportSide(
                id: idAwayTeam?.text,
                name: away,
                badgeURL: strAwayTeamBadge?.url,
                score: intAwayScore?.int
            ),
            startsAt: TheSportsDBSports.instant(nil, day: day, time: strEventTime?.text), day: day,
            status: TheSportsDBSports.status(strStatus?.text ?? strProgress?.text), progress: strProgress?.text,
            venue: nil, round: nil, imageURL: nil
        )
    }
}

private struct WireBroadcast: Decodable {
    let strChannel: Loose?
    let strCountry: Loose?
    let strLogo: Loose?

    var broadcast: SportBroadcast? {
        strChannel?.text.map { SportBroadcast(channel: $0, country: strCountry?.text, logoURL: strLogo?.url) }
    }
}
