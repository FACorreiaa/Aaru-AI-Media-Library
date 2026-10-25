import AaruCore
import Foundation

/// SPT-001 · what a user can follow in Sports: a league (or promotion: UFC, WWE), a team, or a
/// player (a fighter or wrestler too). Catalog data by the provider's id; never a Title.
enum SportEntityKind: String, Sendable, CaseIterable, Codable {
    case league, team, player
}

/// One league, team or player as the sports provider lists it.
struct SportEntity: Sendable, Equatable {
    var kind: SportEntityKind
    var id: String
    var name: String
    /// The provider's sport name: "Soccer", "Basketball", "American Football", "Fighting".
    var sport: String
    var badgeURL: URL?
    var country: String?
    /// A team's main league; a player's team's league once known.
    var leagueID: String?
    /// A player's team. A fighter's "team" is their division, which belongs to the promotion.
    var teamID: String?
    var teamName: String?
}

/// Where a sport event stands, from the provider's free-text status.
enum SportEventStatus: String, Sendable, Equatable {
    case scheduled, live, finished, postponed, cancelled
}

/// One side of a match. Cards (a UFC or WWE event) have no sides.
struct SportSide: Sendable, Equatable {
    var id: String?
    var name: String
    var badgeURL: URL?
    var score: Int?
}

/// SPT-002 · one match, game, race or card. Catalog data for the Sports tab only: never a Title,
/// never a library row, and kept no longer than the cache.
struct SportEvent: Sendable, Equatable {
    var id: String
    var sport: String
    var name: String
    var leagueID: String?
    var league: String?
    var leagueBadgeURL: URL?
    var home: SportSide?
    var away: SportSide?
    /// The exact start in UTC, when the provider has a time.
    var startsAt: Date?
    /// The UTC day, `YYYY-MM-DD`.
    var day: String
    var status: SportEventStatus
    /// The live clock or period as the provider says it: "67", "HT", "Q3".
    var progress: String?
    var venue: String?
    var round: String?
    var imageURL: URL?

    /// Whether this event involves the team (as home or away).
    func involves(team id: String) -> Bool {
        home?.id == id || away?.id == id
    }
}

/// One channel showing an event, in one country.
struct SportBroadcast: Sendable, Equatable {
    var channel: String
    var country: String?
    var logoURL: URL?
}

enum SportScheduleDirection: String, Sendable {
    case next, previous
}

/// Sports data from a provider (TheSportsDB today). Named for the job, not the vendor.
protocol SportsListing: Sendable {
    /// Up to ten matches by name.
    func search(_ kind: SportEntityKind, _ query: String) async throws -> [SportEntity]
    /// Nil when the provider does not know the id.
    func lookup(_ kind: SportEntityKind, id: String) async throws -> SportEntity?
    /// A team's or league's next or previous events (`kind` is `.team` or `.league`).
    func schedule(_ direction: SportScheduleDirection, _ kind: SportEntityKind, id: String) async throws
        -> [SportEvent]
    /// A league's events on one UTC day (`YYYY-MM-DD`).
    func events(day: String, leagueID: String) async throws -> [SportEvent]
    func event(id: String) async throws -> SportEvent?
    /// Every event the provider follows live right now, all sports (football, NFL, NBA, MLB,
    /// NHL), with its clock and score. Laid over listed events by id.
    func live() async throws -> [SportEvent]
    func broadcasts(eventID: String) async throws -> [SportBroadcast]
}

/// A followed league, team or player, with what was known of it when followed so the list
/// renders while the provider is down.
struct SportFollow: Sendable, Equatable {
    var entity: SportEntity
    var createdAt: Date
}

protocol SportsStore: Sendable {
    /// Oldest first.
    func follows(userID: UserID) async throws -> [SportFollow]
    /// Saves or refreshes a follow. False when the user is at `limit` and this one is new.
    func follow(_ entity: SportEntity, userID: UserID, limit: Int, now: Date) async throws -> Bool
    func unfollow(kind: SportEntityKind, id: String, userID: UserID) async throws
    /// ISO 3166-1 alpha-2, uppercase; nil when never chosen.
    func watchCountry(userID: UserID) async throws -> String?
    func saveWatchCountry(_ code: String?, userID: UserID, now: Date) async throws
}
