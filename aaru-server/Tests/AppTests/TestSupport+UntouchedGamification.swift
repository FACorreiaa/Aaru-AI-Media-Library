import AaruCore
import Foundation
@testable import aaru

extension UntouchedStore: GamificationStore {
    func award(_: [PointsAward], userID _: UserID, now _: Date) async throws -> Int {
        throw Touched()
    }

    func revoke(roots _: [String], userID _: UserID) async throws -> Int {
        throw Touched()
    }

    func totalPoints(userID _: UserID) async throws -> Int {
        throw Touched()
    }

    func rebuildTotal(userID _: UserID) async throws -> Int {
        throw Touched()
    }

    func boardPoints(userID _: UserID, from _: String, until _: String) async throws -> Int {
        throw Touched()
    }

    func events(userID _: UserID, before _: Date?, limit _: Int) async throws -> [PointsEvent] {
        throw Touched()
    }

    func streakDays(userID _: UserID) async throws -> [StreakDay] {
        throw Touched()
    }

    func timeZone(userID _: UserID) async throws -> TimeZone {
        throw Touched()
    }

    func markStreakDay(userID _: UserID, now _: Date) async throws {
        throw Touched()
    }

    func backfillStreakDays(userID _: UserID) async throws {
        throw Touched()
    }

    func facts(userID _: UserID) async throws -> AchievementFacts {
        throw Touched()
    }

    func badges(userID _: UserID) async throws -> [EarnedBadge] {
        throw Touched()
    }

    func insertBadges(
        _: [(badge: String, tier: Int)], userID _: UserID, origin _: BadgeOrigin, actionID _: UUID?, now _: Date
    ) async throws -> [EarnedBadge] {
        throw Touched()
    }

    func deleteBadges(ids _: [UUID], userID _: UserID) async throws {
        throw Touched()
    }

    func markBadgesSeen(ids _: [UUID], userID _: UserID, now _: Date) async throws {
        throw Touched()
    }

    func isFresh(userID _: UserID) async throws -> Bool {
        throw Touched()
    }

    func markDirty(userID _: UserID, origin _: BadgeOrigin) async throws {
        throw Touched()
    }

    func claimDirty(lease _: TimeInterval) async throws -> DirtyProgress? {
        throw Touched()
    }

    func finishEvaluation(userID _: UserID, startedAt _: Date) async throws {
        throw Touched()
    }

    func seedProgress(limit _: Int) async throws -> Int {
        throw Touched()
    }

    func leaderboard(viewer _: UserID, from _: String, until _: String) async throws
        -> [(userID: UserID, points: Int)]
    {
        throw Touched()
    }
}
