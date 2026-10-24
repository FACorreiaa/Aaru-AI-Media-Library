import AaruCore
import Foundation
import Testing
@testable import aaru

/// A sports provider that records what it was asked. Test-only.
final class FakeSports: SportsListing, @unchecked Sendable {
    // @unchecked: `lock` guards every mutable field.
    private let lock = NSLock()
    private var calls: [String] = []
    private var failing = false
    private var latency: Duration?
    var entities: [String: SportEntity] = [:]
    var searchHits: [SportEntity] = []
    var schedules: [String: [SportEvent]] = [:]
    var days: [String: [SportEvent]] = [:]
    var events: [String: SportEvent] = [:]
    var liveEvents: [SportEvent] = []
    var channels: [String: [SportBroadcast]] = [:]

    var asked: [String] {
        lock.withLock { calls }
    }

    func fail(_ fails: Bool) {
        lock.withLock { failing = fails }
    }

    func delay(_ duration: Duration?) {
        lock.withLock { latency = duration }
    }

    private func record(_ call: String) async throws {
        let (fails, wait) = lock.withLock {
            calls.append(call)
            return (failing, latency)
        }
        if let wait {
            try await Task.sleep(for: wait)
        }
        if fails {
            throw ProviderError(provider: "thesportsdb", kind: .unavailable)
        }
    }

    func search(_ kind: SportEntityKind, _ query: String) async throws -> [SportEntity] {
        try await record("search:\(kind.rawValue):\(query)")
        return searchHits.filter { $0.kind == kind }
    }

    func lookup(_ kind: SportEntityKind, id: String) async throws -> SportEntity? {
        try await record("lookup:\(kind.rawValue):\(id)")
        return entities["\(kind.rawValue):\(id)"]
    }

    func schedule(
        _ direction: SportScheduleDirection,
        _ kind: SportEntityKind,
        id: String
    ) async throws -> [SportEvent] {
        try await record("schedule:\(direction.rawValue):\(kind.rawValue):\(id)")
        return schedules["\(direction.rawValue):\(kind.rawValue):\(id)"] ?? []
    }

    func events(day: String, leagueID: String) async throws -> [SportEvent] {
        try await record("day:\(leagueID):\(day)")
        return days["\(leagueID):\(day)"] ?? []
    }

    func event(id: String) async throws -> SportEvent? {
        try await record("event:\(id)")
        return events[id]
    }

    func live() async throws -> [SportEvent] {
        try await record("live")
        return liveEvents
    }

    func broadcasts(eventID: String) async throws -> [SportBroadcast] {
        try await record("tv:\(eventID)")
        return channels[eventID] ?? []
    }
}

func sampleMatch(
    _ id: String, home: String, away: String, league: String = "4328", at timestamp: String,
    status: SportEventStatus = .scheduled, homeScore: Int? = nil, awayScore: Int? = nil
) -> SportEvent {
    let startsAt = ISO8601DateFormatter().date(from: timestamp)
    return SportEvent(
        id: id, sport: "Soccer", name: "Team \(home) vs Team \(away)", leagueID: league, league: "League \(league)",
        leagueBadgeURL: nil,
        home: SportSide(id: home, name: "Team \(home)", badgeURL: nil, score: homeScore),
        away: SportSide(id: away, name: "Team \(away)", badgeURL: nil, score: awayScore),
        startsAt: startsAt, day: String(timestamp.prefix(10)), status: status, progress: nil, venue: nil, round: nil,
        imageURL: nil
    )
}
