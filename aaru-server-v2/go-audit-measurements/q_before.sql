
SELECT due.track_key, due.album_key, due.artist, due.track, due.album, due.recording_mbid, due.isrc FROM (
    SELECT DISTINCT ON (l.track_key, lower(coalesce(l.album, '')))
           l.track_key, lower(coalesce(l.album, ''))::text AS album_key, l.artist, l.track, l.album,
           l.recording_mbid, l.isrc, l.listened_at
    FROM listens l
    WHERE l.release_group_mbid IS NULL
      AND NOT EXISTS (
          SELECT 1 FROM music_lookups m
          WHERE m.track_key = l.track_key AND m.album_key = lower(coalesce(l.album, ''))
            AND (m.release_group_mbid IS NOT NULL OR m.looked_up_at > now() - interval '7 days')
      )
    ORDER BY l.track_key, lower(coalesce(l.album, '')), l.recording_mbid IS NULL, l.isrc IS NULL,
             l.listened_at DESC
) due
ORDER BY due.listened_at DESC
LIMIT 30;
