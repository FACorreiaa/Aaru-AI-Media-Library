import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// MUS-004 · listening history imports: a job's plays are staged, counted against the log with the
/// live duplicate window, written as the job's `import` listens, and deleted with it on undo.
extension PostgresListenStore {
    /// Rows per staging INSERT: 17 binds a row stays far under Postgres's 65,535.
    static let stageChunk = 1000

    func stage(_ listens: [NewListen], jobID: ImportJobID, from index: Int) async throws {
        let sql = try sqlDatabase(database)
        for start in stride(from: 0, to: listens.count, by: Self.stageChunk) {
            let chunk = listens[start ..< min(start + Self.stageChunk, listens.count)]
            let values = SQLList(chunk.indices.map { position in
                let listen = listens[position]
                return SQLQueryString("""
                (\(bind: jobID.rawValue), \(bind: index + position), \(bind: listen.listenedAt), \(bind: listen.artist),
                 \(bind: listen.track), \(bind: listen.album), \(bind: listen.trackKey), \(bind: listen.durationMs),
                 \(bind: listen.isrc), \(bind: listen.recordingMBID), \(bind: listen.releaseMBID),
                 \(bind: listen.releaseGroupMBID), \(bind: listen.artistMBID), \(bind: listen.spotifyID),
                 \(bind: listen.originURL), \(bind: listen.client), \(bind: listen.musicService))
                """)
            })
            try await sql.raw("""
            INSERT INTO import_listens
                (job_id, idx, listened_at, artist, track, album, track_key, duration_ms, isrc, recording_mbid,
                 release_mbid, release_group_mbid, artist_mbid, spotify_id, origin_url, client, music_service)
            VALUES \(values)
            """).run()
        }
    }

    func clearStaged(jobID: ImportJobID) async throws {
        try await sqlDatabase(database).raw("DELETE FROM import_listens WHERE job_id = \(bind: jobID.rawValue)").run()
    }

    /// The job's staged plays that applying keeps. Each play's window is the live one: half its
    /// length, at most 90 s, 30 s when unknown. A play repeated inside the file is compared with
    /// the one just before it of the same track, as sending them one by one in time order would.
    private func kept(jobID: ImportJobID, userID: UserID) -> SQLQueryString {
        """
        SELECT s.* FROM (
            SELECT staged.*,
                   coalesce(least(90, staged.duration_ms / 2000.0), 30)::float8 AS window_secs,
                   lag(staged.listened_at) OVER (PARTITION BY staged.track_key ORDER BY staged.listened_at, staged.idx)
                       AS previous_at
            FROM import_listens staged WHERE staged.job_id = \(bind: jobID.rawValue)
        ) s
        WHERE (s.previous_at IS NULL OR s.listened_at - s.previous_at > make_interval(secs => s.window_secs))
          AND NOT EXISTS (
              SELECT 1 FROM listens l
              WHERE l.user_id = \(bind: userID.rawValue) AND l.track_key = s.track_key
                AND l.listened_at BETWEEN s.listened_at - make_interval(secs => s.window_secs)
                                      AND s.listened_at + make_interval(secs => s.window_secs)
          )
        """
    }

    private struct Counted: Decodable { let count: Int }

    func countNew(jobID: ImportJobID, userID: UserID) async throws -> Int {
        try await sqlDatabase(database).raw("""
        SELECT count(*)::int AS count FROM (\(kept(jobID: jobID, userID: userID))) k
        """).first(decoding: Counted.self)?.count ?? 0
    }

    func applyStaged(jobID: ImportJobID, userID: UserID) async throws -> Int {
        try await database.transaction { transaction in
            let sql = try sqlDatabase(transaction)
            // The same per-user lock as a scrobbler's insert, so a live listen arriving now is
            // compared with these, or these with it.
            try await sql.raw("""
            SELECT pg_advisory_xact_lock(hashtextextended('listens:' || \(bind: userID.rawValue.uuidString), 0))
            """).run()
            // A track MusicBrainz already identified (MUS-006) gets its ids now, as a live one does.
            let written = try await sql.raw("""
            WITH kept AS (\(kept(jobID: jobID, userID: userID))),
            written AS (
                INSERT INTO listens
                    (id, user_id, listened_at, artist, track, album, track_key, duration_ms, isrc, recording_mbid,
                     release_mbid, release_group_mbid, artist_mbid, spotify_id, origin_url, client, music_service,
                     source, import_job_id)
                SELECT gen_random_uuid(), \(bind: userID.rawValue), k.listened_at, k.artist, k.track, k.album,
                       k.track_key, k.duration_ms, k.isrc, coalesce(k.recording_mbid, m.recording_mbid),
                       k.release_mbid, coalesce(k.release_group_mbid, m.release_group_mbid),
                       coalesce(k.artist_mbid, m.artist_mbid), k.spotify_id, k.origin_url, k.client,
                       k.music_service, 'import', \(bind: jobID.rawValue)
                FROM kept k
                LEFT JOIN music_lookups m ON m.track_key = k.track_key AND m.album_key = lower(coalesce(k.album, ''))
                ON CONFLICT (user_id, track_key, listened_at) DO NOTHING
                RETURNING 1
            )
            SELECT count(*)::int AS count FROM written
            """).first(decoding: Counted.self)?.count ?? 0
            try await sql.raw("DELETE FROM import_listens WHERE job_id = \(bind: jobID.rawValue)").run()
            return written
        }
    }

    func deleteImported(jobID: ImportJobID, userID: UserID) async throws -> Int {
        try await sqlDatabase(database).raw("""
        WITH deleted AS (
            DELETE FROM listens
            WHERE user_id = \(bind: userID.rawValue) AND import_job_id = \(bind: jobID.rawValue)
            RETURNING 1
        )
        SELECT count(*)::int AS count FROM deleted
        """).first(decoding: Counted.self)?.count ?? 0
    }

    func newestImported(userID: UserID, source: ImportSource, account: String) async throws -> Date? {
        struct Newest: Decodable { let newest: Date? }
        return try await sqlDatabase(database).raw("""
        SELECT max(l.listened_at) AS newest
        FROM listens l JOIN import_jobs j ON j.id = l.import_job_id
        WHERE l.user_id = \(bind: userID.rawValue) AND j.user_id = \(bind: userID.rawValue)
          AND j.source = \(bind: source.rawValue) AND lower(j.filename) = lower(\(bind: account))
        """).first(decoding: Newest.self)?.newest
    }
}
