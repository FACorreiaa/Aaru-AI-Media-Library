-- MUS-005/006/004 · the listening log (PostgresListenStore.swift, PostgresListenStore+Imports.swift).
-- The top lists vary their GROUP BY, so they live in internal/music/store.go.

-- name: LockUserListens :exec
-- One writer per user at a time, so two scrobblers sending the same play at once cannot both pass
-- the duplicate check.
SELECT pg_advisory_xact_lock(hashtextextended('listens:' || sqlc.arg(user_key)::text, 0));

-- name: InsertListen :one
-- A track MusicBrainz already identified (MUS-006) gets its ids now, not on the next pass. Nothing is
-- written inside a stored listen's duplicate window, nor (SCR-011) inside the same YouTube video's
-- own length.
INSERT INTO listens
    (id, user_id, listened_at, artist, track, album, track_key, duration_ms, isrc, recording_mbid,
     release_mbid, release_group_mbid, artist_mbid, spotify_id, origin_url, client, music_service,
     source, agent_token_id)
SELECT sqlc.arg(id)::uuid, sqlc.arg(user_id)::uuid, sqlc.arg(listened_at)::timestamptz, sqlc.arg(artist)::text,
       sqlc.arg(track)::text, sqlc.narg(album)::text, sqlc.arg(track_key)::text, sqlc.narg(duration_ms)::int,
       sqlc.narg(isrc)::text,
       coalesce(sqlc.narg(recording_mbid)::text, (
           SELECT m.recording_mbid FROM music_lookups m WHERE m.track_key = sqlc.arg(track_key)::text
             AND m.album_key = lower(coalesce(sqlc.narg(album)::text, '')))),
       sqlc.narg(release_mbid)::text,
       coalesce(sqlc.narg(release_group_mbid)::text, (
           SELECT m.release_group_mbid FROM music_lookups m WHERE m.track_key = sqlc.arg(track_key)::text
             AND m.album_key = lower(coalesce(sqlc.narg(album)::text, '')))),
       coalesce(sqlc.narg(artist_mbid)::text, (
           SELECT m.artist_mbid FROM music_lookups m WHERE m.track_key = sqlc.arg(track_key)::text
             AND m.album_key = lower(coalesce(sqlc.narg(album)::text, '')))),
       sqlc.narg(spotify_id)::text,
       sqlc.narg(origin_url)::text, sqlc.narg(client)::text, sqlc.narg(music_service)::text, 'live',
       sqlc.narg(agent_token_id)::uuid
WHERE NOT EXISTS (
    SELECT 1 FROM listens l
    WHERE l.user_id = sqlc.arg(user_id)::uuid AND l.track_key = sqlc.arg(track_key)::text
      AND l.listened_at BETWEEN sqlc.arg(listened_at)::timestamptz - make_interval(secs => sqlc.arg(window_secs)::float8)
                            AND sqlc.arg(listened_at)::timestamptz + make_interval(secs => sqlc.arg(window_secs)::float8)
)
AND (sqlc.narg(video_id)::text IS NULL OR NOT EXISTS (
    SELECT 1 FROM listens l
    WHERE l.user_id = sqlc.arg(user_id)::uuid
      AND l.listened_at BETWEEN sqlc.arg(listened_at)::timestamptz - make_interval(secs => sqlc.arg(video_window_secs)::float8)
                            AND sqlc.arg(listened_at)::timestamptz + make_interval(secs => sqlc.arg(video_window_secs)::float8)
      AND substring(l.origin_url from sqlc.arg(video_pattern)::text) = sqlc.narg(video_id)::text
))
ON CONFLICT (user_id, track_key, listened_at) DO NOTHING
RETURNING id;

-- name: ListenPage :many
-- Newest first, older than `before` when it is set.
SELECT l.id, l.listened_at, l.artist, l.track, l.album, l.duration_ms, l.release_group_mbid,
       t.id AS album_title_id, l.origin_url, l.client, l.music_service
FROM listens l
LEFT JOIN titles t ON t.musicbrainz = l.release_group_mbid
WHERE l.user_id = sqlc.arg(user_id)::uuid
  AND (sqlc.narg(before)::timestamptz IS NULL OR l.listened_at < sqlc.narg(before)::timestamptz)
ORDER BY l.listened_at DESC, l.id DESC
LIMIT sqlc.arg(max_rows)::bigint;

-- name: UnresolvedListens :many
-- One row per track and album: the listen with the most ids, then the newest, speaks for it.
SELECT due.track_key, due.album_key, due.artist, due.track, due.album, due.recording_mbid, due.isrc FROM (
    SELECT DISTINCT ON (l.track_key, lower(coalesce(l.album, '')))
           l.track_key, lower(coalesce(l.album, ''))::text AS album_key, l.artist, l.track, l.album,
           l.recording_mbid, l.isrc, l.listened_at
    FROM listens l
    WHERE l.release_group_mbid IS NULL
      AND NOT EXISTS (
          SELECT 1 FROM music_lookups m
          WHERE m.track_key = l.track_key AND m.album_key = lower(coalesce(l.album, ''))
            AND (m.release_group_mbid IS NOT NULL OR m.looked_up_at > sqlc.arg(retry_before)::timestamptz)
      )
    ORDER BY l.track_key, lower(coalesce(l.album, '')), l.recording_mbid IS NULL, l.isrc IS NULL,
             l.listened_at DESC
) due
ORDER BY due.listened_at DESC
LIMIT sqlc.arg(max_rows)::int;

-- name: SaveMusicLookup :exec
INSERT INTO music_lookups (track_key, album_key, recording_mbid, release_group_mbid, artist_mbid, looked_up_at)
VALUES (sqlc.arg(track_key)::text, sqlc.arg(album_key)::text, sqlc.narg(recording_mbid)::text,
        sqlc.narg(release_group_mbid)::text, sqlc.narg(artist_mbid)::text, sqlc.arg(looked_up_at)::timestamptz)
ON CONFLICT (track_key, album_key) DO UPDATE SET
    recording_mbid = excluded.recording_mbid, release_group_mbid = excluded.release_group_mbid,
    artist_mbid = excluded.artist_mbid, looked_up_at = excluded.looked_up_at;

-- name: FillListenIDs :execrows
-- Ids a scrobbler sent are never overwritten.
UPDATE listens SET
    recording_mbid = coalesce(recording_mbid, sqlc.narg(recording_mbid)::text),
    release_group_mbid = coalesce(release_group_mbid, sqlc.narg(release_group_mbid)::text),
    artist_mbid = coalesce(artist_mbid, sqlc.narg(artist_mbid)::text)
WHERE track_key = sqlc.arg(track_key)::text AND lower(coalesce(album, '')) = sqlc.arg(album_key)::text
  AND release_group_mbid IS NULL;

-- MARK: MUS-004 · listening history imports

-- StageListens is a COPY in internal/music/store.go: sqlc rejects a many-array unnest.

-- name: ClearStagedListens :exec
DELETE FROM import_listens WHERE job_id = sqlc.arg(job_id)::uuid;

-- name: CountNewStagedListens :one
-- The job's staged plays that applying keeps. Each play's window is the live one: half its length, at
-- most 90 s, 30 s when unknown. A play repeated inside the file is compared with the one just before it
-- of the same track, as sending them one by one in time order would.
SELECT count(*)::int FROM (
    SELECT staged.listened_at, staged.track_key,
           coalesce(least(90, staged.duration_ms / 2000.0), 30)::float8 AS window_secs,
           lag(staged.listened_at) OVER (PARTITION BY staged.track_key ORDER BY staged.listened_at, staged.idx)
               AS previous_at
    FROM import_listens staged WHERE staged.job_id = sqlc.arg(job_id)::uuid
) s
WHERE (s.previous_at IS NULL OR s.listened_at - s.previous_at > make_interval(secs => s.window_secs))
  AND NOT EXISTS (
      SELECT 1 FROM listens l
      WHERE l.user_id = sqlc.arg(user_id)::uuid AND l.track_key = s.track_key
        AND l.listened_at BETWEEN s.listened_at - make_interval(secs => s.window_secs)
                              AND s.listened_at + make_interval(secs => s.window_secs)
  );

-- name: ApplyStagedListens :one
-- Writes the plays CountNewStagedListens counts as the job's `import` listens. A track MusicBrainz
-- already identified (MUS-006) gets its ids now, as a live one does.
WITH kept AS (
    SELECT s.* FROM (
        SELECT staged.*,
               coalesce(least(90, staged.duration_ms / 2000.0), 30)::float8 AS window_secs,
               lag(staged.listened_at) OVER (PARTITION BY staged.track_key ORDER BY staged.listened_at, staged.idx)
                   AS previous_at
        FROM import_listens staged WHERE staged.job_id = sqlc.arg(job_id)::uuid
    ) s
    WHERE (s.previous_at IS NULL OR s.listened_at - s.previous_at > make_interval(secs => s.window_secs))
      AND NOT EXISTS (
          SELECT 1 FROM listens l
          WHERE l.user_id = sqlc.arg(user_id)::uuid AND l.track_key = s.track_key
            AND l.listened_at BETWEEN s.listened_at - make_interval(secs => s.window_secs)
                                  AND s.listened_at + make_interval(secs => s.window_secs)
      )
),
written AS (
    INSERT INTO listens
        (id, user_id, listened_at, artist, track, album, track_key, duration_ms, isrc, recording_mbid,
         release_mbid, release_group_mbid, artist_mbid, spotify_id, origin_url, client, music_service,
         source, import_job_id)
    SELECT gen_random_uuid(), sqlc.arg(user_id)::uuid, k.listened_at, k.artist, k.track, k.album,
           k.track_key, k.duration_ms, k.isrc, coalesce(k.recording_mbid, m.recording_mbid),
           k.release_mbid, coalesce(k.release_group_mbid, m.release_group_mbid),
           coalesce(k.artist_mbid, m.artist_mbid), k.spotify_id, k.origin_url, k.client,
           k.music_service, 'import', sqlc.arg(job_id)::uuid
    FROM kept k
    LEFT JOIN music_lookups m ON m.track_key = k.track_key AND m.album_key = lower(coalesce(k.album, ''))
    ON CONFLICT (user_id, track_key, listened_at) DO NOTHING
    RETURNING 1
)
SELECT count(*)::int FROM written;

-- name: DeleteImportedListens :execrows
DELETE FROM listens WHERE user_id = sqlc.arg(user_id)::uuid AND import_job_id = sqlc.arg(job_id)::uuid;

-- name: NewestImportedListen :one
-- The newest listen an applied import of this source and account wrote.
SELECT max(l.listened_at)::timestamptz AS newest
FROM listens l JOIN import_jobs j ON j.id = l.import_job_id
WHERE l.user_id = sqlc.arg(user_id)::uuid AND j.user_id = sqlc.arg(user_id)::uuid
  AND j.source = sqlc.arg(source)::text AND lower(j.filename) = lower(sqlc.arg(account)::text);
