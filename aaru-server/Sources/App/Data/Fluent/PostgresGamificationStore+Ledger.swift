import AaruCore
import FluentSQL
import Foundation

// MARK: Shared with the library transaction

extension PostgresGamificationStore {
    // swiftlint:disable function_parameter_count
    /// Points and the streak day for one live library write, inside its transaction, from the op
    /// and the inverse the store computed (ARCHITECTURE.md §Gamification).
    static func recordLibraryWrite(
        op: LibraryOp,
        inverse: LibraryOp,
        kind: String,
        caller: Caller,
        actionID: UUID,
        userID: UserID,
        requestedZone: TimeZone?,
        sql: any SQLDatabase,
        now: Date = Date()
    ) async throws {
        // swiftlint:enable function_parameter_count
        let facts = LibraryWriteFacts.derive(op: op, inverse: inverse, kind: kind)
        guard !facts.isEmpty else { return }
        let items = try await itemTitles(Array(facts.itemIDs), sql: sql)
        let zone = try await zone(userID: userID, requested: requestedZone, sql: sql)
        let date = Streak.localDate(now, in: zone)
        var awards = try await tickAwards(facts.ticked, items: items, caller: caller, actionID: actionID, sql: sql)
        awards += finishAwards(facts, items: items, caller: caller, actionID: actionID, date: date)
        let revokes = revokedRoots(facts, items: items)
        if !revokes.isEmpty {
            try await revoke(roots: revokes, userID: userID, sql: sql)
        }
        if !awards.isEmpty {
            try await award(awards, userID: userID, zone: zone, now: now, sql: sql)
        }
        if awards.contains(where: \.kind.marksStreakDay) {
            try await markStreakDay(userID: userID, zone: zone, now: now, sql: sql)
        }
    }

    /// An episode each, a scrobble bonus each when a player sent it, and a season bonus for every
    /// season the ticks completed.
    private static func tickAwards(
        _ ticked: [LibraryItemID: [EpisodeKey]], items: [LibraryItemID: (id: TitleID, type: MediaType)],
        caller: Caller, actionID: UUID, sql: any SQLDatabase
    ) async throws -> [PointsAward] {
        var awards: [PointsAward] = []
        for (item, keys) in ticked {
            guard let title = items[item] else { continue }
            for key in keys {
                awards.append(PointsAward(
                    .episode, root: PointsRoot.episode(title.id, key), titleID: title.id, actionID: actionID
                ))
                if caller.scrobbled {
                    awards.append(PointsAward(
                        .scrobbleBonus, root: PointsRoot.scrobble(title.id, key), titleID: title.id, actionID: actionID
                    ))
                }
            }
            for season in Set(keys.map(\.season)) where season > 0 {
                if try await seasonComplete(item: item, title: title.id, season: season, sql: sql) {
                    awards.append(PointsAward(
                        .seasonBonus, root: PointsRoot.season(title.id, season), titleID: title.id, actionID: actionID
                    ))
                }
            }
        }
        return awards
    }

    private static func finishAwards(
        _ facts: LibraryWriteFacts, items: [LibraryItemID: (id: TitleID, type: MediaType)], caller: Caller,
        actionID: UUID, date: String
    ) -> [PointsAward] {
        var awards: [PointsAward] = []
        for item in facts.finished {
            guard let title = items[item], let finish = finishKind(title.type) else { continue }
            awards.append(PointsAward(finish, root: PointsRoot.finish(title.id), titleID: title.id, actionID: actionID))
            if caller.scrobbled {
                awards.append(PointsAward(
                    .scrobbleBonus, root: PointsRoot.scrobbleFinish(title.id), titleID: title.id, actionID: actionID
                ))
            }
        }
        for item in facts.bookForward {
            guard let title = items[item], title.type == .book else { continue }
            awards.append(PointsAward(
                .bookProgress, root: PointsRoot.bookDay(title.id, date), titleID: title.id, actionID: actionID
            ))
        }
        return awards
    }

    /// Unticked episodes and their seasons, and finishes taken back.
    private static func revokedRoots(
        _ facts: LibraryWriteFacts, items: [LibraryItemID: (id: TitleID, type: MediaType)]
    ) -> [String] {
        var revokes: [String] = []
        for (item, keys) in facts.unticked {
            guard let title = items[item] else { continue }
            revokes += keys.flatMap { [PointsRoot.episode(title.id, $0), PointsRoot.scrobble(title.id, $0)] }
            revokes += Set(keys.map(\.season)).map { PointsRoot.season(title.id, $0) }
        }
        for item in facts.unfinished {
            guard let title = items[item] else { continue }
            revokes += [PointsRoot.finish(title.id), PointsRoot.scrobbleFinish(title.id)]
        }
        return revokes
    }

    static func finishKind(_ type: MediaType) -> PointsKind? {
        switch type {
        case .movie: .movieFinished
        case .book: .bookFinished
        case .album: .albumFinished
        case .show: nil
        }
    }

    /// The request's zone (stored for later requests that send none), else the stored zone,
    /// else UTC. Inside a Fluent transaction the task-local is gone, so callers there read
    /// `ClientTimeZone.current` before opening it and pass it as `requested`.
    static func zone(
        userID: UserID, requested: TimeZone? = ClientTimeZone.current, sql: any SQLDatabase
    ) async throws -> TimeZone {
        if let zone = requested {
            try await sql.raw("""
            INSERT INTO user_progress (user_id, time_zone) VALUES (\(bind: userID.rawValue), \(bind: zone.identifier))
            ON CONFLICT (user_id) DO UPDATE SET time_zone = EXCLUDED.time_zone
            WHERE user_progress.time_zone IS DISTINCT FROM EXCLUDED.time_zone
            """).run()
            return zone
        }
        struct Row: Decodable { let timeZone: String? }
        let stored = try await sql.raw("""
        SELECT time_zone FROM user_progress WHERE user_id = \(bind: userID.rawValue)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)?.timeZone
        return stored.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "UTC") ?? .current
    }

    static func markStreakDay(userID: UserID, zone: TimeZone, now: Date, sql: any SQLDatabase) async throws {
        try await sql.raw("""
        INSERT INTO check_ins (user_id, local_date, time_zone, first_at)
        VALUES (\(bind: userID.rawValue), \(bind: Streak.localDate(now, in: zone))::date, \(bind: zone.identifier),
            \(bind: now))
        ON CONFLICT (user_id, local_date) DO NOTHING
        """).run()
    }

    /// Writes the awards whose root has no active award (or no event at all, for once-only kinds), trimmed to each
    /// kind's daily cap. A
    /// capped award is still written at 0 points, so the root stays spent.
    @discardableResult
    static func award(
        _ awards: [PointsAward], userID: UserID, zone: TimeZone, now: Date, sql: any SQLDatabase
    ) async throws -> Int {
        var seen = Set<String>()
        let unique = awards.filter { seen.insert($0.root).inserted }
        guard !unique.isEmpty else { return 0 }
        let last = try await lastEvents(roots: unique.map(\.root), userID: userID, sql: sql)
        var due = unique.filter { award in
            guard let event = last[award.root] else { return true }
            return event.revoked && !award.kind.oncePerRoot
        }
        guard !due.isEmpty else { return 0 }
        let date = Streak.localDate(now, in: zone)
        var remaining = try await earnedToday(
            kinds: Set(due.compactMap { $0.kind.dailyCap == nil ? nil : $0.kind }), userID: userID, date: date,
            sql: sql
        )
        for index in due.indices {
            guard let cap = due[index].kind.dailyCap else { continue }
            let left = max(0, cap - remaining[due[index].kind, default: 0])
            due[index].points = min(due[index].points, left)
            remaining[due[index].kind, default: 0] += due[index].points
        }
        let seqs = due.map { (last[$0.root]?.seq ?? 0) + 1 }
        struct Row: Decodable { let points: Int }
        let written = try await sql.raw("""
        INSERT INTO points_events (id, user_id, kind, points, dedupe_root, seq, dedupe_key, title_id, action_id,
            local_date, time_zone, created_at)
        SELECT k.id, \(bind: userID.rawValue), k.kind, k.points, k.root, k.seq, k.root || '#' || k.seq,
            NULLIF(k.title, '')::uuid, NULLIF(k.action, '')::uuid, \(bind: date)::date, \(bind: zone.identifier),
            \(bind: now)
        FROM unnest(\(bind: due.map { _ in UUID() })::uuid[], \(bind: due.map(\.kind.rawValue))::text[],
                    \(bind: due.map(\.points))::int[], \(bind: due.map(\.root))::text[], \(bind: seqs)::int[],
                    \(bind: due.map { $0.titleID?.rawValue.uuidString ?? "" })::text[],
                    \(bind: due.map { $0.actionID?.uuidString ?? "" })::text[])
            AS k(id, kind, points, root, seq, title, action)
        ON CONFLICT (user_id, dedupe_key) DO NOTHING
        RETURNING points
        """).all(decoding: Row.self)
        let total = written.reduce(0) { $0 + $1.points }
        try await addToTotal(total, userID: userID, sql: sql)
        return total
    }

    /// Writes the negative of each root's active award, on the award's own local date so an old
    /// undo never dents this week's board.
    @discardableResult
    static func revoke(roots: [String], userID: UserID, sql: any SQLDatabase) async throws -> Int {
        let last = try await lastEvents(roots: Array(Set(roots)), userID: userID, sql: sql)
        let active = last.values.filter { !$0.revoked }
        guard !active.isEmpty else { return 0 }
        struct Row: Decodable { let points: Int }
        let written = try await sql.raw("""
        INSERT INTO points_events (id, user_id, kind, points, dedupe_root, seq, dedupe_key, reverses, title_id,
            local_date, time_zone)
        SELECT gen_random_uuid(), e.user_id, e.kind, -e.points, e.dedupe_root, e.seq + 1,
            e.dedupe_root || '#' || (e.seq + 1), e.id, e.title_id, e.local_date, e.time_zone
        FROM points_events e WHERE e.id = ANY(\(bind: active.map(\.id))::uuid[])
        ON CONFLICT (user_id, dedupe_key) DO NOTHING
        RETURNING points
        """).all(decoding: Row.self)
        let total = written.reduce(0) { $0 + $1.points }
        try await addToTotal(total, userID: userID, sql: sql)
        return total
    }

    private struct LastEvent: Decodable {
        let id: UUID
        let dedupeRoot: String
        let seq: Int
        let revoked: Bool
    }

    private static func lastEvents(roots: [String], userID: UserID, sql: any SQLDatabase) async throws
        -> [String: LastEvent]
    {
        let rows = try await sql.raw("""
        SELECT DISTINCT ON (dedupe_root) id, dedupe_root, seq, reverses IS NOT NULL AS revoked
        FROM points_events
        WHERE user_id = \(bind: userID.rawValue) AND dedupe_root = ANY(\(bind: roots)::text[])
        ORDER BY dedupe_root, seq DESC
        """).all(decoding: LastEvent.self, keyDecodingStrategy: .convertFromSnakeCase)
        return Dictionary(rows.map { ($0.dedupeRoot, $0) }) { first, _ in first }
    }

    private static func earnedToday(
        kinds: Set<PointsKind>, userID: UserID, date: String, sql: any SQLDatabase
    ) async throws -> [PointsKind: Int] {
        guard !kinds.isEmpty else { return [:] }
        struct Row: Decodable {
            let kind: String
            let total: Int
        }
        let rows = try await sql.raw("""
        SELECT kind, COALESCE(sum(points), 0)::int AS total FROM points_events
        WHERE user_id = \(bind: userID.rawValue) AND local_date = \(bind: date)::date
          AND kind = ANY(\(bind: kinds.map(\.rawValue))::text[])
        GROUP BY kind
        """).all(decoding: Row.self)
        let pairs = rows.compactMap { row in PointsKind(rawValue: row.kind).map { ($0, row.total) } }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    private static func addToTotal(_ delta: Int, userID: UserID, sql: any SQLDatabase) async throws {
        guard delta != 0 else { return }
        try await sql.raw("""
        INSERT INTO user_progress (user_id, total_points) VALUES (\(bind: userID.rawValue), \(bind: delta))
        ON CONFLICT (user_id) DO UPDATE
        SET total_points = user_progress.total_points + EXCLUDED.total_points, updated_at = now()
        """).run()
    }

    private struct ItemTitle: Decodable {
        let itemId: UUID
        let titleId: UUID
        let type: String
    }

    private static func itemTitles(_ items: [LibraryItemID], sql: any SQLDatabase) async throws
        -> [LibraryItemID: (id: TitleID, type: MediaType)]
    {
        let rows = try await sql.raw("""
        SELECT li.id AS item_id, t.id AS title_id, t.type FROM library_items li JOIN titles t ON t.id = li.title_id
        WHERE li.id = ANY(\(bind: items.map(\.rawValue))::uuid[])
        """).all(decoding: ItemTitle.self, keyDecodingStrategy: .convertFromSnakeCase)
        var titles: [LibraryItemID: (id: TitleID, type: MediaType)] = [:]
        for row in rows {
            if let type = MediaType(rawValue: row.type) {
                titles[LibraryItemID(row.itemId)] = (TitleID(row.titleId), type)
            }
        }
        return titles
    }

    /// Every aired regular episode of the season is ticked.
    private static func seasonComplete(
        item: LibraryItemID, title: TitleID, season: Int, sql: any SQLDatabase
    ) async throws -> Bool {
        struct Row: Decodable {
            let aired: Int
            let missing: Int
        }
        guard let row = try await sql.raw("""
        SELECT count(*)::int AS aired, count(*) FILTER (WHERE ep.id IS NULL)::int AS missing
        FROM show_episodes se JOIN titles t ON t.id = se.title_id
        LEFT JOIN episode_progress ep ON ep.library_item_id = \(bind: item.rawValue)
            AND ep.season = se.season AND ep.episode = se.episode
        WHERE se.title_id = \(bind: title.rawValue) AND se.season = \(bind: season)
          AND (se.airs_at <= now() OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')))
        """).first(decoding: Row.self)
        else { return false }
        return row.aired > 0 && row.missing == 0
    }
}
