import AaruCore
import Foundation
import Logging

/// The user's level, streak and what is new, as `/v1/me/progress` returns it.
struct PointsProgress: Sendable, Equatable {
    var total: Int
    var level: Int
    var levelStart: Int
    var nextLevelAt: Int
    var weekPoints: Int
    var streak: StreakSummary
    /// The last seven local dates, oldest first, and whether each was a streak day.
    var days: [(date: String, active: Bool)]
    var unseen: [EarnedBadge]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.total == rhs.total && lhs.level == rhs.level && lhs.weekPoints == rhs.weekPoints
            && lhs.streak == rhs.streak && lhs.unseen == rhs.unseen
            && lhs.days.map(\.date) == rhs.days.map(\.date) && lhs.days.map(\.active) == rhs.days.map(\.active)
    }
}

/// One catalog badge with what the user has of it.
struct BadgeStatus: Sendable {
    var definition: BadgeDefinition
    /// Earned tiers, lowest first.
    var earned: [EarnedBadge]
    var value: Int

    var tier: Int {
        earned.map(\.tier).max() ?? 0
    }

    /// The next threshold, nil once every tier is earned.
    var target: Int? {
        tier < definition.maxTier ? definition.thresholds[tier] : nil
    }
}

/// One weekly board (GAM-005).
struct Leaderboard: Sendable {
    var week: String
    var from: String
    var until: String
    var optedIn: Bool
    var entries: [Entry]

    struct Entry: Sendable {
        var user: SocialUser
        var points: Int
        var rank: Int
    }
}

/// An ISO week (Monday to Sunday) by name and local dates.
struct ISOWeek: Sendable, Equatable {
    var name: String
    var from: String
    var until: String
}

/// Points, streaks, badges and the board (GAM-001…005). Every award goes through the store's
/// idempotent ledger (X-010). The after-write hooks are best effort: a failure logs and leaves
/// the user dirty for `GamificationWorker`, and never fails the write that triggered it.
struct GamificationService: Sendable {
    let stores: Stores
    var now: @Sendable () -> Date = { Date() }
    var logger = Logger(label: "aaru.gamification")

    static let friendReversalWindow: TimeInterval = 7 * 24 * 60 * 60
    static let listenWindow: TimeInterval = 24 * 60 * 60

    private var store: any GamificationStore {
        stores.gamification
    }

    // MARK: Hooks

    /// After a live library or list write: streak bonuses, then badges.
    func afterWrite(userID: UserID, actionID: UUID?) async {
        await bestEffort(userID) {
            try await streakBonuses(userID)
            _ = try await evaluate(userID, origin: .live, actionID: actionID)
        }
    }

    /// After an undo: take back tiers the undone action earned and no longer holds, then
    /// evaluate as usual.
    func afterUndo(userID: UserID, undone: UUID, undoAction: UUID) async {
        await bestEffort(userID) {
            try await takeBack(userID, undone: undone)
            _ = try await evaluate(userID, origin: .live, actionID: undoAction)
        }
    }

    /// A mutual friendship began: both earn, once per pair.
    func friendAdded(_ first: UserID, _ second: UserID) async {
        let root = PointsRoot.friend(first, second)
        for user in [first, second] {
            await bestEffort(user) {
                try await store.award([PointsAward(.friendAdded, root: root)], userID: user, now: now())
                _ = try await evaluate(user, origin: .live, actionID: nil)
            }
        }
    }

    /// A friendship ended. Under seven days old, both lose its points; re-friending earns nothing.
    func friendEnded(_ first: UserID, _ second: UserID, since: Date) async {
        guard now().timeIntervalSince(since) < Self.friendReversalWindow else { return }
        let root = PointsRoot.friend(first, second)
        for user in [first, second] {
            await bestEffort(user) {
                try await store.revoke(roots: [root], userID: user)
            }
        }
    }

    /// The user was in a watch party, once per party.
    func roomAttended(_ user: UserID, session: UUID) async {
        await bestEffort(user) {
            try await store.award(
                [PointsAward(.roomAttended, root: PointsRoot.room(session))],
                userID: user,
                now: now()
            )
            _ = try await evaluate(user, origin: .live, actionID: nil)
        }
    }

    /// Listens a scrobbler just sent. Only listens from the last day earn points (a backlog is
    /// not a day's listening); every listen counts toward music badges. Listens keep no streak.
    func listensKept(_ user: UserID, listens: [NewListen]) async {
        guard !listens.isEmpty else { return }
        let fresh = listens.filter { now().timeIntervalSince($0.listenedAt) <= Self.listenWindow }
        await bestEffort(user) {
            if !fresh.isEmpty {
                try await store.award(
                    fresh.map { PointsAward(.listen, root: PointsRoot.listen($0)) },
                    userID: user,
                    now: now()
                )
            }
            _ = try await evaluate(user, origin: .live, actionID: nil)
        }
    }

    /// An import or an approved plan was applied: no points per item, and its badges arrive as
    /// one summary. Undoing that action takes back what it earned.
    func batchApplied(_ user: UserID, actionID: UUID?, firstImport: Bool) async {
        do {
            if firstImport {
                try await store.award(
                    [PointsAward(.importFirst, root: PointsRoot.importFirst)],
                    userID: user,
                    now: now()
                )
            }
            _ = try await evaluate(user, origin: .batch, actionID: actionID)
        } catch {
            logger.error("Gamification step failed", metadata: ["error": "\(error)"])
            try? await store.markDirty(userID: user, origin: .batch)
        }
    }

    // MARK: Evaluation

    /// Awards every tier the facts reach and the user lacks. A user never evaluated before gets
    /// their live streak days backfilled first, and the result is one summary, not a toast each.
    @discardableResult
    func evaluate(_ user: UserID, origin: BadgeOrigin, actionID: UUID?) async throws -> [EarnedBadge] {
        let started = now()
        var origin = origin
        if try await store.isFresh(userID: user) {
            try await store.backfillStreakDays(userID: user)
            origin = .backfill
        }
        let facts = try await store.facts(userID: user)
        let earned = try await store.badges(userID: user)
        let have = Set(earned.map { "\($0.badge)#\($0.tier)" })
        var due: [(badge: String, tier: Int)] = []
        for definition in BadgeCatalog.all {
            let reached = definition.tier(for: facts)
            guard reached > 0 else { continue }
            for tier in 1 ... reached where !have.contains("\(definition.id)#\(tier)") {
                due.append((definition.id, tier))
            }
        }
        let inserted = try await store.insertBadges(
            due, userID: user, origin: origin, actionID: origin == .backfill ? nil : actionID, now: started
        )
        try await store.finishEvaluation(userID: user, startedAt: started)
        return inserted
    }

    /// Tiers the undone action earned whose rule no longer holds.
    func takeBack(_ user: UserID, undone: UUID) async throws {
        let earned = try await store.badges(userID: user).filter { $0.actionID == undone }
        guard !earned.isEmpty else { return }
        let facts = try await store.facts(userID: user)
        let lost = earned.filter { badge in
            BadgeCatalog.byID[badge.badge].map { badge.tier > $0.tier(for: facts) } ?? false
        }
        try await store.deleteBadges(ids: lost.map(\.id), userID: user)
    }

    /// Milestone bonuses for the live run: once per run per milestone.
    func streakBonuses(_ user: UserID) async throws {
        let zone = try await store.timeZone(userID: user)
        let summary = try await Streak.summarize(
            store.streakDays(userID: user), today: Streak.localDate(now(), in: zone)
        )
        guard let start = summary.runStart else { return }
        let awards = Streak.milestones.filter { summary.current >= $0 }.map {
            PointsAward(
                .streakMilestone,
                root: PointsRoot.streak(runStart: start, days: $0),
                points: PointsKind.streakBonus(days: $0)
            )
        }
        if !awards.isEmpty {
            try await store.award(awards, userID: user, now: now())
        }
    }

    // MARK: Reads

    func progress(_ user: UserID) async throws -> PointsProgress {
        let zone = try await store.timeZone(userID: user)
        let today = Streak.localDate(now(), in: zone)
        let total = try await store.totalPoints(userID: user)
        let level = Levels.level(for: total)
        let week = Self.week(containing: today)
        let days = try await store.streakDays(userID: user)
        let dates = Set(days.map(\.date))
        let lastSeven = (0 ..< 7).reversed().compactMap { Streak.adding(-$0, to: today) }
        let unseen = try await store.badges(userID: user).filter { $0.seenAt == nil }
        return try await PointsProgress(
            total: total, level: level, levelStart: Levels.threshold(level), nextLevelAt: Levels.threshold(level + 1),
            weekPoints: store.boardPoints(userID: user, from: week.from, until: week.until),
            streak: Streak.summarize(days, today: today),
            days: lastSeven.map { ($0, dates.contains($0)) },
            unseen: unseen.sorted { $0.awardedAt > $1.awardedAt }
        )
    }

    func badges(_ user: UserID) async throws -> [BadgeStatus] {
        let facts = try await store.facts(userID: user)
        let earned = try Dictionary(grouping: await store.badges(userID: user), by: \.badge)
        return BadgeCatalog.all.map { definition in
            BadgeStatus(
                definition: definition,
                earned: (earned[definition.id] ?? []).sorted { $0.tier < $1.tier },
                value: definition.value(facts)
            )
        }
    }

    func markSeen(_ ids: [UUID], user: UserID) async throws {
        try await store.markBadgesSeen(ids: ids, userID: user, now: now())
    }

    /// What a friend may see: level and non-private earned badges, newest first. Nil when they
    /// turned the switch off.
    func friendAchievements(_ friend: UserID) async throws -> (level: Int, badges: [EarnedBadge])? {
        guard try await stores.friendViews.socialSettings(friend).showAchievementsToFriends else { return nil }
        let total = try await store.totalPoints(userID: friend)
        let badges = try await store.badges(userID: friend).filter {
            BadgeCatalog.byID[$0.badge].map { !$0.isPrivate } ?? false
        }
        // One medallion per badge, its highest tier.
        let top = Dictionary(grouping: badges, by: \.badge).compactMap { $0.value.max { $0.tier < $1.tier } }
        return (Levels.level(for: total), top.sorted { $0.awardedAt > $1.awardedAt })
    }

    func leaderboard(viewer: UserID, week requested: String?) async throws -> Leaderboard {
        let zone = try await store.timeZone(userID: viewer)
        let today = Streak.localDate(now(), in: zone)
        var week = Self.week(containing: today)
        if let requested {
            guard let named = Self.week(named: requested) else {
                throw AppError(status: .badRequest, code: "bad_request", message: "Weeks look like 2026-W43.")
            }
            week = named
        }
        let optedIn = try await stores.friendViews.socialSettings(viewer).leaderboardOptIn
        var rows: [(userID: UserID, points: Int)] = []
        if optedIn {
            rows = try await store.leaderboard(viewer: viewer, from: week.from, until: week.until)
        }
        var people = try await stores.social.friends(viewer)
        if let own = try await stores.social.socialUser(viewer) {
            people.append(own)
        }
        var byID: [UserID: SocialUser] = [:]
        for person in people {
            byID[person.id] = person
        }
        var standings: [(user: SocialUser, points: Int)] = []
        for row in rows {
            if let user = byID[row.userID] {
                standings.append((user, row.points))
            }
        }
        standings.sort { lhs, rhs in
            lhs.points == rhs.points ? lhs.user.handle < rhs.user.handle : lhs.points > rhs.points
        }
        var entries: [Leaderboard.Entry] = []
        for (index, row) in standings.enumerated() {
            let tied = index > 0 && standings[index - 1].points == row.points
            entries.append(.init(user: row.user, points: row.points, rank: tied ? entries[index - 1].rank : index + 1))
        }
        return Leaderboard(week: week.name, from: week.from, until: week.until, optedIn: optedIn, entries: entries)
    }

    // MARK: Weeks

    /// The ISO week (Monday to Sunday) holding a local date.
    static func week(containing date: String) -> ISOWeek {
        let day = Streak.dayNumber(date) ?? 0
        // 1970-01-01 was a Thursday: Monday-based weekday 3.
        let weekday = ((day % 7) + 7 + 3) % 7
        let monday = day - weekday
        let from = Streak.adding(monday - day, to: date) ?? date
        let until = Streak.adding(6, to: from) ?? date
        let thursday = Streak.adding(3, to: from) ?? date
        let year = Int(thursday.prefix(4)) ?? 1970
        let firstThursday = (1 ... 7).compactMap { offset -> Int? in
            let candidate = String(format: "%04d-01-%02d", year, offset)
            guard let number = Streak.dayNumber(candidate) else { return nil }
            return ((number % 7) + 7 + 3) % 7 == 3 ? number : nil
        }.first ?? 0
        let index = ((Streak.dayNumber(thursday) ?? 0) - firstThursday) / 7 + 1
        return ISOWeek(name: String(format: "%04d-W%02d", year, index), from: from, until: until)
    }

    /// `2026-W43` to its Monday and Sunday.
    static func week(named name: String) -> ISOWeek? {
        let parts = name.split(separator: "-W")
        guard parts.count == 2, let year = Int(parts[0]), let index = Int(parts[1]), (1 ... 53).contains(index),
              (1970 ... 9999).contains(year)
        else { return nil }
        // Week 1 holds January 4th.
        let anchor = week(containing: String(format: "%04d-01-04", year))
        guard let monday = Streak.adding((index - 1) * 7, to: anchor.from) else { return nil }
        let found = week(containing: monday)
        return found.name == String(format: "%04d-W%02d", year, index) ? found : nil
    }

    private func bestEffort(_ user: UserID, _ body: () async throws -> Void) async {
        do {
            try await body()
        } catch {
            logger.error("Gamification step failed", metadata: ["error": "\(error)"])
            try? await store.markDirty(userID: user, origin: .live)
        }
    }
}

// MARK: Listening history (MUS-004)

extension GamificationService {
    /// A listening-history import was applied (MUS-004): no points, however recent its listens (a
    /// backlog is not a day's listening). Its music badges arrive as one summary.
    func listensImported(_ user: UserID) async {
        await bestEffort(user) {
            _ = try await evaluate(user, origin: .batch, actionID: nil)
        }
    }

    /// A listening-history import was undone: the music tiers whose rule no longer holds go. The
    /// import is not a journaled action, so its tiers are found by rule rather than by action.
    func listensUndone(_ user: UserID) async {
        await bestEffort(user) {
            let facts = try await store.facts(userID: user)
            let lost = try await store.badges(userID: user).filter { badge in
                BadgeCatalog.byID[badge.badge].map { $0.family == .music && badge.tier > $0.tier(for: facts) } ?? false
            }
            if !lost.isEmpty {
                try await store.deleteBadges(ids: lost.map(\.id), userID: user)
            }
        }
    }
}
