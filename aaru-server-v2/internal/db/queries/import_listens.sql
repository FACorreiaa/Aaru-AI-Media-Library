-- MUS-004 · listening history imports: a job's plays are staged, counted against the log with the
-- live duplicate window, written as the job's `import` listens, and deleted with it on undo.
-- PostgresListenStore+Imports.swift.

-- name: ImportListensStage :copyfrom
INSERT INTO import_listens
    (job_id, idx, listened_at, artist, track, album, track_key, duration_ms, isrc, recording_mbid,
     release_mbid, release_group_mbid, artist_mbid, spotify_id, origin_url, client, music_service)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17);

-- name: ImportListensClear :exec
DELETE FROM import_listens WHERE job_id = @job_id;

-- name: ImportListensCountNew :one
-- The job's staged plays that applying keeps. Each play's window is the live one: half its length,
-- at most 90 s, 30 s when unknown. A play repeated inside the file is compared with the one just
-- before it of the same track, as sending them one by one in time order would.
SELECT count(*)::int AS count FROM (
    SELECT s.* FROM (
        SELECT staged.*,
               coalesce(least(90, staged.duration_ms / 2000.0), 30)::float8 AS window_secs,
               lag(staged.listened_at) OVER (PARTITION BY staged.track_key ORDER BY staged.listened_at, staged.idx)
                   AS previous_at
        FROM import_listens staged WHERE staged.job_id = @job_id::uuid
    ) s
    WHERE (s.previous_at IS NULL OR s.listened_at - s.previous_at > make_interval(secs => s.window_secs))
      AND NOT EXISTS (
          SELECT 1 FROM listens l
          WHERE l.user_id = @user_id::uuid AND l.track_key = s.track_key
            AND l.listened_at BETWEEN s.listened_at - make_interval(secs => s.window_secs)
                                  AND s.listened_at + make_interval(secs => s.window_secs)
      )
) k;

-- name: ImportListensLock :exec
-- The same per-user lock as a scrobbler's insert, so a live listen arriving now is compared with
-- these, or these with it. The key is the user id as Swift's uuidString wrote it: uppercase.
SELECT pg_advisory_xact_lock(hashtextextended('listens:' || @user_key::text, 0));

-- name: ImportListensApply :one
-- Writes the kept plays as the job's `import` listens. A track MusicBrainz already identified
-- (MUS-006) gets its ids now, as a live one does.
WITH kept AS (
    SELECT s.* FROM (
        SELECT staged.*,
               coalesce(least(90, staged.duration_ms / 2000.0), 30)::float8 AS window_secs,
               lag(staged.listened_at) OVER (PARTITION BY staged.track_key ORDER BY staged.listened_at, staged.idx)
                   AS previous_at
        FROM import_listens staged WHERE staged.job_id = @job_id::uuid
    ) s
    WHERE (s.previous_at IS NULL OR s.listened_at - s.previous_at > make_interval(secs => s.window_secs))
      AND NOT EXISTS (
          SELECT 1 FROM listens l
          WHERE l.user_id = @user_id::uuid AND l.track_key = s.track_key
            AND l.listened_at BETWEEN s.listened_at - make_interval(secs => s.window_secs)
                                  AND s.listened_at + make_interval(secs => s.window_secs)
      )
),
written AS (
    INSERT INTO listens
        (id, user_id, listened_at, artist, track, album, track_key, duration_ms, isrc, recording_mbid,
         release_mbid, release_group_mbid, artist_mbid, spotify_id, origin_url, client, music_service,
         source, import_job_id)
    SELECT gen_random_uuid(), @user_id::uuid, k.listened_at, k.artist, k.track, k.album,
           k.track_key, k.duration_ms, k.isrc, coalesce(k.recording_mbid, m.recording_mbid),
           k.release_mbid, coalesce(k.release_group_mbid, m.release_group_mbid),
           coalesce(k.artist_mbid, m.artist_mbid), k.spotify_id, k.origin_url, k.client,
           k.music_service, 'import', @job_id::uuid
    FROM kept k
    LEFT JOIN music_lookups m ON m.track_key = k.track_key AND m.album_key = lower(coalesce(k.album, ''))
    ON CONFLICT (user_id, track_key, listened_at) DO NOTHING
    RETURNING 1
)
SELECT count(*)::int AS count FROM written;

-- name: ImportListensDeleteImported :execrows
DELETE FROM listens WHERE user_id = @user_id AND import_job_id = @job_id;

-- name: ImportListensNewestImported :one
-- The newest listen an applied import of this source and account wrote (Swift: max(listened_at)).
SELECT l.listened_at
FROM listens l JOIN import_jobs j ON j.id = l.import_job_id
WHERE l.user_id = @user_id AND j.user_id = @user_id
  AND j.source = @source AND lower(j.filename) = lower(@account::text)
ORDER BY l.listened_at DESC
LIMIT 1;
