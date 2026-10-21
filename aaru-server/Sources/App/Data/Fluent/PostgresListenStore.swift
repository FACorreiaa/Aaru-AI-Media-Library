import AaruCore
import FluentKit
import FluentSQL
import Foundation

struct PostgresListenStore: ListenStore {
    let database: any Database

    func insert(_ listens: [NewListen], userID: UserID, agentTokenID: UUID?) async throws -> Int {
        guard !listens.isEmpty else { return 0 }
        return try await database.transaction { transaction in
            let sql = try sqlDatabase(transaction)
            // One writer per user at a time, so two scrobblers sending the same play at once
            // cannot both pass the duplicate check.
            try await sql.raw("""
            SELECT pg_advisory_xact_lock(hashtextextended('listens:' || \(bind: userID.rawValue.uuidString), 0))
            """).run()
            var kept = 0
            for listen in listens {
                kept += try await insert(listen, userID: userID, agentTokenID: agentTokenID, sql: sql) ? 1 : 0
            }
            return kept
        }
    }

    private func insert(_ listen: NewListen, userID: UserID, agentTokenID: UUID?, sql: any SQLDatabase) async throws
        -> Bool
    {
        struct Inserted: Decodable { let id: UUID }
        let key = listen.trackKey
        let window = listen.duplicateWindow
        return try await sql.raw("""
        INSERT INTO listens
            (id, user_id, listened_at, artist, track, album, track_key, duration_ms, isrc, recording_mbid,
             release_mbid, release_group_mbid, artist_mbid, spotify_id, origin_url, client, music_service,
             source, agent_token_id)
        SELECT \(bind: UUID()), \(bind: userID.rawValue), \(bind: listen.listenedAt), \(bind: listen.artist),
               \(bind: listen.track), \(bind: listen.album), \(bind: key), \(bind: listen.durationMs),
               \(bind: listen.isrc), \(bind: listen.recordingMBID), \(bind: listen.releaseMBID),
               \(bind: listen.releaseGroupMBID), \(bind: listen.artistMBID), \(bind: listen.spotifyID),
               \(bind: listen.originURL), \(bind: listen.client), \(bind: listen.musicService), 'live',
               \(bind: agentTokenID)
        WHERE NOT EXISTS (
            SELECT 1 FROM listens
            WHERE user_id = \(bind: userID.rawValue) AND track_key = \(bind: key)
              AND listened_at BETWEEN \(bind: listen.listenedAt) - make_interval(secs => \(bind: window))
                                  AND \(bind: listen.listenedAt) + make_interval(secs => \(bind: window))
        )
        ON CONFLICT (user_id, track_key, listened_at) DO NOTHING
        RETURNING id
        """).first(decoding: Inserted.self) != nil
    }

    private struct Row: Decodable {
        let id: UUID
        let listenedAt: Date
        let artist: String
        let track: String
        let album: String?
        let durationMs: Int?
        let releaseGroupMbid: String?
        let originUrl: String?
        let client: String?
        let musicService: String?

        var listen: Listen {
            Listen(
                id: id, listenedAt: listenedAt, artist: artist, track: track, album: album, durationMs: durationMs,
                releaseGroupMBID: releaseGroupMbid, originURL: originUrl, client: client, musicService: musicService
            )
        }
    }

    func listens(userID: UserID, before: Date?, limit: Int) async throws -> [Listen] {
        let sql = try sqlDatabase(database)
        return try await sql.raw("""
        SELECT id, listened_at, artist, track, album, duration_ms, release_group_mbid, origin_url, client,
               music_service
        FROM listens
        WHERE user_id = \(bind: userID.rawValue)
          AND (\(bind: before)::timestamptz IS NULL OR listened_at < \(bind: before))
        ORDER BY listened_at DESC, id DESC
        LIMIT \(bind: limit)
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.listen)
    }

    private struct Totals: Decodable {
        let listens: Int
        let durationMs: Int64
    }

    private struct Ranked: Decodable {
        let artist: String
        let track: String
        let album: String?
        let count: Int
        let durationMs: Int64
    }

    func top(userID: UserID, by grouping: ListenGrouping, period: StatsPeriod, limit: Int) async throws -> ListenTop {
        let sql = try sqlDatabase(database)
        let zone = period.timeZone.identifier
        let inPeriod: SQLQueryString = """
        user_id = \(bind: userID.rawValue)
          AND (listened_at AT TIME ZONE \(bind: zone))::date >= \(bind: period.start.description)::date
          AND (listened_at AT TIME ZONE \(bind: zone))::date < \(bind: period.end.description)::date
        """
        let totals = try await sql.raw("""
        SELECT count(*)::int AS listens, coalesce(sum(duration_ms), 0)::bigint AS duration_ms
        FROM listens WHERE \(inPeriod)
        """).first(decoding: Totals.self, keyDecodingStrategy: .convertFromSnakeCase)
        // Grouped by the folded spelling; the newest listen's spelling is the one shown.
        let artistKey = "split_part(track_key, chr(31), 1)"
        let key = switch grouping {
        case .artist: artistKey
        case .track: "track_key"
        case .album: "\(artistKey) || chr(31) || lower(album)"
        }
        let rows = try await sql.raw("""
        SELECT (array_agg(artist ORDER BY listened_at DESC))[1] AS artist,
               (array_agg(track ORDER BY listened_at DESC))[1] AS track,
               (array_agg(album ORDER BY listened_at DESC))[1] AS album,
               count(*)::int AS count, coalesce(sum(duration_ms), 0)::bigint AS duration_ms
        FROM listens
        WHERE \(inPeriod) \(unsafeRaw: grouping == .album ? "AND album IS NOT NULL" : "")
        GROUP BY \(unsafeRaw: key)
        ORDER BY count(*) DESC, sum(duration_ms) DESC NULLS LAST, \(unsafeRaw: key)
        LIMIT \(bind: limit)
        """).all(decoding: Ranked.self, keyDecodingStrategy: .convertFromSnakeCase)
        return ListenTop(
            period: period,
            listens: totals?.listens ?? 0,
            durationMs: totals?.durationMs ?? 0,
            items: rows.map { row in
                ListenTotal(
                    artist: row.artist,
                    track: grouping == .track ? row.track : nil,
                    album: grouping == .album ? row.album : nil,
                    count: row.count, durationMs: row.durationMs
                )
            }
        )
    }
}
