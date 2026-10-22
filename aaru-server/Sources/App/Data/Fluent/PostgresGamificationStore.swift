import AaruCore
import FluentSQL
import Foundation

/// The points ledger, streak days and badges (GAM-001…005). Library writes record their points
/// inside the library's own transaction through `recordLibraryWrite`; everything else goes
/// through the instance methods.
struct PostgresGamificationStore: GamificationStore {
    let sql: any SQLDatabase

    // MARK: Ledger

    func award(_ awards: [PointsAward], userID: UserID, now: Date) async throws -> Int {
        let zone = try await Self.zone(userID: userID, sql: sql)
        return try await Self.award(awards, userID: userID, zone: zone, now: now, sql: sql)
    }

    func revoke(roots: [String], userID: UserID) async throws -> Int {
        try await Self.revoke(roots: roots, userID: userID, sql: sql)
    }

    func totalPoints(userID: UserID) async throws -> Int {
        struct Row: Decodable { let totalPoints: Int }
        return try await sql.raw("""
        SELECT total_points FROM user_progress WHERE user_id = \(bind: userID.rawValue)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)?.totalPoints ?? 0
    }

    func rebuildTotal(userID: UserID) async throws -> Int {
        struct Row: Decodable { let total: Int }
        let total = try await sql.raw("""
        SELECT COALESCE(sum(points), 0)::int AS total FROM points_events WHERE user_id = \(bind: userID.rawValue)
        """).first(decoding: Row.self)?.total ?? 0
        try await sql.raw("""
        INSERT INTO user_progress (user_id, total_points) VALUES (\(bind: userID.rawValue), \(bind: total))
        ON CONFLICT (user_id) DO UPDATE SET total_points = EXCLUDED.total_points, updated_at = now()
        """).run()
        return total
    }

    func boardPoints(userID: UserID, from: String, until: String) async throws -> Int {
        struct Row: Decodable { let total: Int }
        return try await sql.raw("""
        SELECT COALESCE(sum(points), 0)::int AS total FROM points_events
        WHERE user_id = \(bind: userID.rawValue) AND local_date BETWEEN \(bind: from)::date AND \(bind: until)::date
          AND kind <> ALL(\(bind: Self.offBoardKinds)::text[])
        """).first(decoding: Row.self)?.total ?? 0
    }

    func events(userID: UserID, before: Date?, limit: Int) async throws -> [PointsEvent] {
        struct Row: Decodable {
            let id: UUID
            let kind: String
            let points: Int
            let titleId: UUID?
            let localDate: String
            let createdAt: Date
            let isRevocation: Bool
        }
        let rows = try await sql.raw("""
        SELECT id, kind, points, title_id, to_char(local_date, 'YYYY-MM-DD') AS local_date, created_at,
            reverses IS NOT NULL AS is_revocation
        FROM points_events
        WHERE user_id = \(bind: userID.rawValue) AND created_at < \(bind: before ?? .distantFuture)
        ORDER BY created_at DESC, seq DESC
        LIMIT \(bind: limit)
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        return rows.map {
            PointsEvent(
                id: $0.id, kind: $0.kind, points: $0.points, titleID: $0.titleId.map(TitleID.init),
                localDate: $0.localDate, createdAt: $0.createdAt, isRevocation: $0.isRevocation
            )
        }
    }

    // MARK: Streak days

    func streakDays(userID: UserID) async throws -> [StreakDay] {
        struct Row: Decodable {
            let localDate: String
            let timeZone: String
            let firstAt: Date
        }
        return try await sql.raw("""
        SELECT to_char(local_date, 'YYYY-MM-DD') AS local_date, time_zone, first_at FROM check_ins
        WHERE user_id = \(bind: userID.rawValue) ORDER BY local_date
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            StreakDay(date: $0.localDate, timeZone: $0.timeZone, firstAt: $0.firstAt)
        }
    }

    func timeZone(userID: UserID) async throws -> TimeZone {
        try await Self.zone(userID: userID, sql: sql)
    }

    func markStreakDay(userID: UserID, now: Date) async throws {
        let zone = try await Self.zone(userID: userID, sql: sql)
        try await Self.markStreakDay(userID: userID, zone: zone, now: now, sql: sql)
    }

    func backfillStreakDays(userID: UserID) async throws {
        let zone = try await Self.zone(userID: userID, sql: sql)
        // Only ticks the user made live: imported and restored ticks carry write time, not
        // when they watched (GAM-006a's rule).
        try await sql.raw("""
        INSERT INTO check_ins (user_id, local_date, time_zone, first_at)
        SELECT \(bind: userID.rawValue), (ep.watched_at AT TIME ZONE \(bind: zone.identifier))::date,
            \(bind: zone.identifier), min(ep.watched_at)
        FROM episode_progress ep JOIN library_items li ON li.id = ep.library_item_id
        WHERE li.user_id = \(bind: userID.rawValue) AND ep.watched_at_known
        GROUP BY 2
        ON CONFLICT (user_id, local_date) DO NOTHING
        """).run()
    }

    // MARK: Badges

    func badges(userID: UserID) async throws -> [EarnedBadge] {
        try await sql.raw("""
        SELECT id, badge, tier, awarded_at, origin, action_id, seen_at FROM user_badges
        WHERE user_id = \(bind: userID.rawValue) ORDER BY awarded_at, badge, tier
        """).all(decoding: BadgeRow.self, keyDecodingStrategy: .convertFromSnakeCase).compactMap(\.earned)
    }

    func insertBadges(
        _ tiers: [(badge: String, tier: Int)], userID: UserID, origin: BadgeOrigin, actionID: UUID?, now: Date
    ) async throws -> [EarnedBadge] {
        guard !tiers.isEmpty else { return [] }
        return try await sql.raw("""
        INSERT INTO user_badges (id, user_id, badge, tier, awarded_at, origin, action_id)
        SELECT k.id, \(bind: userID.rawValue), k.badge, k.tier, \(bind: now), \(bind: origin.rawValue),
            \(bind: actionID)
        FROM unnest(\(bind: tiers.map { _ in UUID() })::uuid[], \(bind: tiers.map(\.badge))::text[],
                    \(bind: tiers.map(\.tier))::int[]) AS k(id, badge, tier)
        ON CONFLICT (user_id, badge, tier) DO NOTHING
        RETURNING id, badge, tier, awarded_at, origin, action_id, seen_at
        """).all(decoding: BadgeRow.self, keyDecodingStrategy: .convertFromSnakeCase).compactMap(\.earned)
    }

    func deleteBadges(ids: [UUID], userID: UserID) async throws {
        guard !ids.isEmpty else { return }
        try await sql.raw("""
        DELETE FROM user_badges WHERE user_id = \(bind: userID.rawValue) AND id = ANY(\(bind: ids)::uuid[])
        """).run()
    }

    func markBadgesSeen(ids: [UUID], userID: UserID, now: Date) async throws {
        guard !ids.isEmpty else { return }
        try await sql.raw("""
        UPDATE user_badges SET seen_at = \(bind: now)
        WHERE user_id = \(bind: userID.rawValue) AND id = ANY(\(bind: ids)::uuid[]) AND seen_at IS NULL
        """).run()
    }

    // MARK: Worker

    func isFresh(userID: UserID) async throws -> Bool {
        struct Row: Decodable { let evaluatedAt: Date? }
        let row = try await sql.raw("""
        SELECT evaluated_at FROM user_progress WHERE user_id = \(bind: userID.rawValue)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        return row?.evaluatedAt == nil
    }

    func markDirty(userID: UserID, origin: BadgeOrigin) async throws {
        // A batch outranks a live mark: one summary instead of a toast per badge.
        try await sql.raw("""
        INSERT INTO user_progress (user_id, dirty_at, dirty_origin)
        VALUES (\(bind: userID.rawValue), now(), \(bind: origin.rawValue))
        ON CONFLICT (user_id) DO UPDATE SET dirty_at = now(),
            dirty_origin = CASE
                WHEN user_progress.dirty_origin IN ('batch', 'backfill') AND user_progress.dirty_at IS NOT NULL
                THEN user_progress.dirty_origin ELSE EXCLUDED.dirty_origin END
        """).run()
    }

    func claimDirty(lease: TimeInterval) async throws -> DirtyProgress? {
        struct Row: Decodable {
            let userId: UUID
            let dirtyOrigin: String?
            let fresh: Bool
        }
        guard let row = try await sql.raw("""
        UPDATE user_progress SET locked_until = now() + make_interval(secs => \(bind: lease))
        WHERE user_id = (
            SELECT user_id FROM user_progress
            WHERE (dirty_at IS NOT NULL OR evaluated_at IS NULL) AND (locked_until IS NULL OR locked_until < now())
            ORDER BY dirty_at NULLS LAST
            LIMIT 1 FOR UPDATE SKIP LOCKED
        )
        RETURNING user_id, dirty_origin, evaluated_at IS NULL AS fresh
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        else { return nil }
        let origin: BadgeOrigin = row.fresh ? .backfill : row.dirtyOrigin.flatMap(BadgeOrigin.init) ?? .live
        return DirtyProgress(userID: UserID(row.userId), origin: origin, fresh: row.fresh)
    }

    func finishEvaluation(userID: UserID, startedAt: Date) async throws {
        try await sql.raw("""
        INSERT INTO user_progress (user_id, evaluated_at) VALUES (\(bind: userID.rawValue), now())
        ON CONFLICT (user_id) DO UPDATE SET evaluated_at = now(), locked_until = NULL,
            dirty_at = CASE WHEN user_progress.dirty_at > \(bind: startedAt) THEN user_progress.dirty_at END,
            dirty_origin = CASE WHEN user_progress.dirty_at > \(bind: startedAt) THEN user_progress.dirty_origin END
        """).run()
    }

    func seedProgress(limit: Int) async throws -> Int {
        struct Row: Decodable { let userId: UUID }
        return try await sql.raw("""
        INSERT INTO user_progress (user_id)
        SELECT u.id FROM users u WHERE NOT EXISTS (SELECT 1 FROM user_progress p WHERE p.user_id = u.id)
        LIMIT \(bind: limit)
        ON CONFLICT (user_id) DO NOTHING
        RETURNING user_id
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).count
    }

    // MARK: Board

    func leaderboard(viewer: UserID, from: String, until: String) async throws -> [(userID: UserID, points: Int)] {
        struct Row: Decodable {
            let id: UUID
            let points: Int
        }
        let rows = try await sql.raw("""
        WITH people AS (
            SELECT CASE WHEN f.user_low = \(bind: viewer.rawValue) THEN f.user_high ELSE f.user_low END AS id
            FROM social_friendships f
            WHERE f.user_low = \(bind: viewer.rawValue) OR f.user_high = \(bind: viewer.rawValue)
            UNION SELECT \(bind: viewer.rawValue)
        )
        SELECT p.id, COALESCE(sum(e.points), 0)::int AS points
        FROM people p
        JOIN social_settings s ON s.user_id = p.id AND s.leaderboard_opt_in
        LEFT JOIN points_events e ON e.user_id = p.id
            AND e.local_date BETWEEN \(bind: from)::date AND \(bind: until)::date
            AND e.kind <> ALL(\(bind: Self.offBoardKinds)::text[])
        WHERE EXISTS (
            SELECT 1 FROM social_settings v WHERE v.user_id = \(bind: viewer.rawValue) AND v.leaderboard_opt_in
        )
        AND NOT EXISTS (
            SELECT 1 FROM social_blocks b
            WHERE (b.blocker_id = \(bind: viewer.rawValue) AND b.blocked_id = p.id)
               OR (b.blocker_id = p.id AND b.blocked_id = \(bind: viewer.rawValue))
        )
        GROUP BY p.id
        """).all(decoding: Row.self)
        return rows.map { (UserID($0.id), $0.points) }
    }

    static let offBoardKinds = PointsKind.allCases.filter { !$0.onBoard }.map(\.rawValue)
}

private struct BadgeRow: Decodable {
    let id: UUID
    let badge: String
    let tier: Int
    let awardedAt: Date
    let origin: String
    let actionId: UUID?
    let seenAt: Date?

    var earned: EarnedBadge? {
        BadgeOrigin(rawValue: origin).map {
            EarnedBadge(
                id: id, badge: badge, tier: tier, awardedAt: awardedAt, origin: $0, actionID: actionId, seenAt: seenAt
            )
        }
    }
}
