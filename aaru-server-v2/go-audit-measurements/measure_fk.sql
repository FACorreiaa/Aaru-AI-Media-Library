\timing on
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF) DELETE FROM users WHERE id = '00000000-0000-0000-0000-00000000beef';
ROLLBACK;
BEGIN;
EXPLAIN (ANALYZE, TIMING OFF) DELETE FROM actions WHERE id = (SELECT id FROM actions WHERE user_id = '00000000-0000-0000-0000-00000000beef' LIMIT 1);
ROLLBACK;
BEGIN;
EXPLAIN (ANALYZE, TIMING OFF) DELETE FROM agent_tokens WHERE id = (SELECT id FROM agent_tokens ORDER BY id LIMIT 1);
ROLLBACK;
-- 100k listens for one user with a token, as scrobbles would arrive (one statement here).
BEGIN;
INSERT INTO listens (id, user_id, listened_at, artist, track, album, track_key, source, agent_token_id)
SELECT gen_random_uuid(), t.user_id, now() + (g || ' seconds')::interval, 'A', 'T' || g, NULL, 'a' || chr(31) || 't' || g, 'live', t.id
FROM (SELECT id, user_id FROM agent_tokens ORDER BY id LIMIT 1) t, generate_series(1, 100000) g;
ROLLBACK;
BEGIN;
INSERT INTO listens (id, user_id, listened_at, artist, track, album, track_key, source, agent_token_id)
SELECT gen_random_uuid(), t.user_id, now() + (g || ' seconds')::interval, 'A', 'T' || g, NULL, 'a' || chr(31) || 't' || g, 'live', t.id
FROM (SELECT id, user_id FROM agent_tokens ORDER BY id LIMIT 1) t, generate_series(1, 100000) g;
ROLLBACK;
