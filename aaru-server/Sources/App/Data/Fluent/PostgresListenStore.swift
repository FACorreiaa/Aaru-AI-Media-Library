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
        // A track MusicBrainz already identified (MUS-006) gets its ids now, not on the next pass.
        let cached: SQLQueryString = """
        FROM music_lookups WHERE track_key = \(bind: key)
          AND album_key = lower(coalesce(\(bind: listen.album)::text, ''))
        """
        return try await sql.raw("""
        INSERT INTO listens
            (id, user_id, listened_at, artist, track, album, track_key, duration_ms, isrc, recording_mbid,
             release_mbid, release_group_mbid, artist_mbid, spotify_id, origin_url, client, music_service,
             source, agent_token_id)
        SELECT \(bind: UUID()), \(bind: userID.rawValue), \(bind: listen.listenedAt), \(bind: listen.artist),
               \(bind: listen.track), \(bind: listen.album), \(bind: key), \(bind: listen.durationMs),
               \(bind: listen.isrc),
               coalesce(\(bind: listen.recordingMBID), (SELECT recording_mbid \(cached))),
               \(bind: listen.releaseMBID),
               coalesce(\(bind: listen.releaseGroupMBID), (SELECT release_group_mbid \(cached))),
               coalesce(\(bind: listen.artistMBID), (SELECT artist_mbid \(cached))),
               \(bind: listen.spotifyID),
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
        let albumTitleId: UUID?
        let originUrl: String?
        let client: String?
        let musicService: String?

        var listen: Listen {
            Listen(
                id: id, listenedAt: listenedAt, artist: artist, track: track, album: album, durationMs: durationMs,
                releaseGroupMBID: releaseGroupMbid, albumTitleID: albumTitleId, originURL: originUrl, client: client,
                musicService: musicService
            )
        }
    }

    func listens(userID: UserID, before: Date?, limit: Int) async throws -> [Listen] {
        let sql = try sqlDatabase(database)
        return try await sql.raw("""
        SELECT l.id, l.listened_at, l.artist, l.track, l.album, l.duration_ms, l.release_group_mbid,
               t.id AS album_title_id, l.origin_url, l.client, l.music_service
        FROM listens l
        LEFT JOIN titles t ON t.musicbrainz = l.release_group_mbid
        WHERE l.user_id = \(bind: userID.rawValue)
          AND (\(bind: before)::timestamptz IS NULL OR l.listened_at < \(bind: before))
        ORDER BY l.listened_at DESC, l.id DESC
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
        let releaseGroupMbid: String?
        let albumTitleId: UUID?
        let count: Int
        let durationMs: Int64
    }

    private func totals(_ sql: any SQLDatabase, where filter: SQLQueryString) async throws -> Totals? {
        try await sql.raw("""
        SELECT count(*)::int AS listens, coalesce(sum(duration_ms), 0)::bigint AS duration_ms
        FROM listens WHERE \(filter)
        """).first(decoding: Totals.self, keyDecodingStrategy: .convertFromSnakeCase)
    }

    func top(userID: UserID, by grouping: ListenGrouping, period: StatsPeriod, limit: Int, artist: String?)
        async throws -> ListenTop
    {
        let sql = try sqlDatabase(database)
        let zone = period.timeZone.identifier
        let artistKey = "split_part(track_key, chr(31), 1)"
        // The period's local midnights as instants, so `listens_user_time` bounds the scan; the
        // same days as comparing each listen's local date, without computing it per row.
        let inPeriod: SQLQueryString = """
        user_id = \(bind: userID.rawValue)
          AND listened_at >= (\(bind: period.start.description)::date)::timestamp AT TIME ZONE \(bind: zone)
          AND listened_at < (\(bind: period.end.description)::date)::timestamp AT TIME ZONE \(bind: zone)
          AND (\(bind: artist.map(Listen.fold))::text IS NULL
               OR \(unsafeRaw: artistKey) = \(bind: artist.map(Listen.fold)))
        """
        let totals = try await totals(sql, where: inPeriod)
        // Grouped by the folded spelling; the newest listen's spelling is the one shown, and the
        // newest identified album gives the row its cover.
        let key = switch grouping {
        case .artist: artistKey
        case .track: "track_key"
        case .album: "\(artistKey) || chr(31) || lower(album)"
        }
        let rows = try await sql.raw("""
        SELECT ranked.*, t.id AS album_title_id FROM (
            SELECT (array_agg(artist ORDER BY listened_at DESC))[1] AS artist,
                   (array_agg(track ORDER BY listened_at DESC))[1] AS track,
                   (array_agg(album ORDER BY listened_at DESC))[1] AS album,
                   (array_agg(release_group_mbid ORDER BY listened_at DESC)
                        FILTER (WHERE release_group_mbid IS NOT NULL))[1] AS release_group_mbid,
                   count(*)::int AS count, coalesce(sum(duration_ms), 0)::bigint AS duration_ms,
                   \(unsafeRaw: key) AS sort_key
            FROM listens
            WHERE \(inPeriod) \(unsafeRaw: grouping == .album ? "AND album IS NOT NULL" : "")
            GROUP BY \(unsafeRaw: key)
            ORDER BY count(*) DESC, sum(duration_ms) DESC NULLS LAST, \(unsafeRaw: key)
            LIMIT \(bind: limit)
        ) ranked
        LEFT JOIN titles t ON t.musicbrainz = ranked.release_group_mbid
        ORDER BY ranked.count DESC, ranked.duration_ms DESC, ranked.sort_key
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
                    count: row.count, durationMs: row.durationMs, releaseGroupMBID: row.releaseGroupMbid,
                    albumTitleID: row.albumTitleId
                )
            }
        )
    }

    private struct Unresolved: Decodable {
        let trackKey: String
        let albumKey: String
        let artist: String
        let track: String
        let album: String?
        let recordingMbid: String?
        let isrc: String?
    }

    func unresolved(retryBefore: Date, limit: Int) async throws -> [ListenLookup] {
        let sql = try sqlDatabase(database)
        // One row per track and album: the listen with the most ids, then the newest, speaks for it.
        return try await sql.raw("""
        SELECT track_key, album_key, artist, track, album, recording_mbid, isrc FROM (
            SELECT DISTINCT ON (l.track_key, lower(coalesce(l.album, '')))
                   l.track_key, lower(coalesce(l.album, '')) AS album_key, l.artist, l.track, l.album,
                   l.recording_mbid, l.isrc, l.listened_at
            FROM listens l
            WHERE l.release_group_mbid IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM music_lookups m
                  WHERE m.track_key = l.track_key AND m.album_key = lower(coalesce(l.album, ''))
                    AND (m.release_group_mbid IS NOT NULL OR m.looked_up_at > \(bind: retryBefore))
              )
            ORDER BY l.track_key, lower(coalesce(l.album, '')), l.recording_mbid IS NULL, l.isrc IS NULL,
                     l.listened_at DESC
        ) due
        ORDER BY listened_at DESC
        LIMIT \(bind: limit)
        """).all(decoding: Unresolved.self, keyDecodingStrategy: .convertFromSnakeCase).map { row in
            ListenLookup(
                trackKey: row.trackKey, albumKey: row.albumKey,
                query: RecordingQuery(
                    artist: row.artist, track: row.track, album: row.album, recordingMBID: row.recordingMbid,
                    isrc: row.isrc
                )
            )
        }
    }

    func resolve(_ lookup: ListenLookup, as match: RecordingMatch, at date: Date) async throws -> Int {
        struct Filled: Decodable { let id: UUID }
        return try await database.transaction { transaction in
            let sql = try sqlDatabase(transaction)
            try await sql.raw("""
            INSERT INTO music_lookups
                (track_key, album_key, recording_mbid, release_group_mbid, artist_mbid, looked_up_at)
            VALUES (\(bind: lookup.trackKey), \(bind: lookup.albumKey), \(bind: match.recordingMBID),
                    \(bind: match.releaseGroupMBID), \(bind: match.artistMBID), \(bind: date))
            ON CONFLICT (track_key, album_key) DO UPDATE SET
                recording_mbid = excluded.recording_mbid, release_group_mbid = excluded.release_group_mbid,
                artist_mbid = excluded.artist_mbid, looked_up_at = excluded.looked_up_at
            """).run()
            // Ids a scrobbler sent are never overwritten.
            let filled = try await sql.raw("""
            UPDATE listens SET
                recording_mbid = coalesce(recording_mbid, \(bind: match.recordingMBID)),
                release_group_mbid = coalesce(release_group_mbid, \(bind: match.releaseGroupMBID)),
                artist_mbid = coalesce(artist_mbid, \(bind: match.artistMBID))
            WHERE track_key = \(bind: lookup.trackKey) AND lower(coalesce(album, '')) = \(bind: lookup.albumKey)
              AND release_group_mbid IS NULL
            RETURNING id
            """).all(decoding: Filled.self).count
            return match.releaseGroupMBID == nil ? 0 : filled
        }
    }
}
