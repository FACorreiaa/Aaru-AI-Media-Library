-- 200 users, 600k unresolved listens over 60k (track, album) keys, every key looked up and missed
-- an hour ago (so none is due), plus 200k resolved listens, plus 50 never-looked-up keys.
INSERT INTO users (id)
SELECT gen_random_uuid() FROM generate_series(1, 200) g;

CREATE TEMP TABLE u AS SELECT id, row_number() OVER () AS n FROM users;

INSERT INTO listens (id, user_id, listened_at, artist, track, album, track_key, source)
SELECT gen_random_uuid(), (SELECT id FROM u WHERE n = 1 + (g % 200)),
       now() - (g || ' seconds')::interval, 'Artist ' || (g % 60000), 'Track ' || (g % 60000),
       'Album ' || (g % 60000), 'artist ' || (g % 60000) || chr(31) || 'track ' || (g % 60000), 'live'
FROM generate_series(1, 600000) g;

INSERT INTO listens (id, user_id, listened_at, artist, track, album, track_key, source, release_group_mbid)
SELECT gen_random_uuid(), (SELECT id FROM u WHERE n = 1 + (g % 200)),
       now() - (g || ' seconds')::interval - interval '30 days', 'R ' || (g % 20000), 'RT ' || (g % 20000),
       'RA ' || (g % 20000), 'r ' || (g % 20000) || chr(31) || 'rt ' || (g % 20000), 'live', 'rg-' || (g % 20000)
FROM generate_series(1, 200000) g;

INSERT INTO music_lookups (track_key, album_key, looked_up_at)
SELECT 'artist ' || k || chr(31) || 'track ' || k, 'album ' || k, now() - interval '1 hour'
FROM generate_series(0, 59999) k;

INSERT INTO listens (id, user_id, listened_at, artist, track, album, track_key, source)
SELECT gen_random_uuid(), (SELECT id FROM u WHERE n = 1), now() - (g || ' minutes')::interval, 'New ' || g,
       'NT ' || g, NULL, 'new ' || g || chr(31) || 'nt ' || g, 'live'
FROM generate_series(1, 50) g;

ANALYZE;
