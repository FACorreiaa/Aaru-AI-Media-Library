import AaruCore
import Foundation

// The points ledger, streak days and badges (GAM-001…005). Part of the data layer boundary in
// Stores.swift.

/// Where an award was evaluated: a live write (toast), an import or approved plan (one summary),
/// or the first run over a user's existing library (one summary).
enum BadgeOrigin: String, Sendable, Codable {
    case live, batch, backfill
}

/// One ledger row as "How you earned it" lists it.
struct PointsEvent: Sendable, Equatable {
    var id: UUID
    var kind: String
    var points: Int
    var titleID: TitleID?
    var localDate: String
    var createdAt: Date
    /// A revocation (an undo, a short friendship).
    var isRevocation: Bool
}

/// One earned badge tier.
struct EarnedBadge: Sendable, Equatable {
    var id: UUID
    var badge: String
    var tier: Int
    var awardedAt: Date
    var origin: BadgeOrigin
    var actionID: UUID?
    var seenAt: Date?
}

/// A user the gamification worker should evaluate, and why.
struct DirtyProgress: Sendable, Equatable {
    var userID: UserID
    var origin: BadgeOrigin
    /// Never evaluated: the first run backfills streak days from live ticks.
    var fresh: Bool
}

protocol GamificationStore: Sendable {
    /// Writes each award whose root's last event is not already an award, within daily caps.
    /// Returns the points actually added.
    @discardableResult
    func award(_ awards: [PointsAward], userID: UserID, now: Date) async throws -> Int
    /// Writes the negative of each root's active award. Returns the points taken back.
    @discardableResult
    func revoke(roots: [String], userID: UserID) async throws -> Int
    func totalPoints(userID: UserID) async throws -> Int
    /// Sums the ledger and stores it as the cached total.
    func rebuildTotal(userID: UserID) async throws -> Int
    /// Points on the weekly board between two local dates, inclusive.
    func boardPoints(userID: UserID, from: String, until: String) async throws -> Int
    func events(userID: UserID, before: Date?, limit: Int) async throws -> [PointsEvent]
    func streakDays(userID: UserID) async throws -> [StreakDay]
    /// The request's zone when it sent one, else the stored zone, else UTC.
    func timeZone(userID: UserID) async throws -> TimeZone
    /// Writes today's streak day for a live write that happened outside the library transaction.
    func markStreakDay(userID: UserID, now: Date) async throws
    /// Streak days from episode ticks the user made live, for a user never evaluated before.
    func backfillStreakDays(userID: UserID) async throws
    func facts(userID: UserID) async throws -> AchievementFacts
    func badges(userID: UserID) async throws -> [EarnedBadge]
    /// Inserts tiers not yet earned; returns the rows it wrote.
    func insertBadges(
        _ tiers: [(badge: String, tier: Int)], userID: UserID, origin: BadgeOrigin, actionID: UUID?, now: Date
    ) async throws -> [EarnedBadge]
    func deleteBadges(ids: [UUID], userID: UserID) async throws
    func markBadgesSeen(ids: [UUID], userID: UserID, now: Date) async throws
    /// Never evaluated: the next evaluation is the first run over an existing library.
    func isFresh(userID: UserID) async throws -> Bool
    func markDirty(userID: UserID, origin: BadgeOrigin) async throws
    /// Leases one user to evaluate: dirty, or never evaluated.
    func claimDirty(lease: TimeInterval) async throws -> DirtyProgress?
    /// Clears the dirty mark unless the user was marked again after `startedAt`.
    func finishEvaluation(userID: UserID, startedAt: Date) async throws
    /// Gives every user without a progress row one, so the worker backfills them.
    func seedProgress(limit: Int) async throws -> Int
    /// The viewer and their friends who joined the board, with this week's points. Blocks are
    /// applied both ways; a viewer who has not joined sees nobody.
    func leaderboard(viewer: UserID, from: String, until: String) async throws -> [(userID: UserID, points: Int)]
}
