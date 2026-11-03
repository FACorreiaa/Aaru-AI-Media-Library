
SELECT d.track_key, d.album_key, r.artist, r.track, r.album, r.recording_mbid, r.isrc
FROM (
    SELECT k.track_key, k.album_key FROM (
        SELECT DISTINCT l.track_key, lower(coalesce(l.album, ''))::text AS album_key
        FROM listens l WHERE l.release_group_mbid IS NULL
    ) k
    WHERE NOT EXISTS (
        SELECT 1 FROM music_lookups m
        WHERE m.track_key = k.track_key AND m.album_key = k.album_key
          AND (m.release_group_mbid IS NOT NULL OR m.looked_up_at > now() - interval '7 days')
    )
) d
CROSS JOIN LATERAL (
    SELECT l.artist, l.track, l.album, l.recording_mbid, l.isrc, l.listened_at
    FROM listens l
    WHERE l.release_group_mbid IS NULL AND l.track_key = d.track_key
      AND lower(coalesce(l.album, '')) = d.album_key
    ORDER BY l.recording_mbid IS NULL, l.isrc IS NULL, l.listened_at DESC
    LIMIT 1
) r
ORDER BY r.listened_at DESC
LIMIT 30;
