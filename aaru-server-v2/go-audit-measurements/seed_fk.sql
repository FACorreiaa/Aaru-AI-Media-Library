-- DB-005 seed: 200k actions platform-wide (1k per user), 5k for one heavy user; each action has a
-- points event; badges and import jobs on some; 200 agent tokens (one per user) on the 600k live listens.
CREATE TEMP TABLE u AS SELECT id, row_number() OVER () AS n FROM users;
INSERT INTO users (id) VALUES ('00000000-0000-0000-0000-00000000beef');

INSERT INTO actions (id, user_id, actor, kind, summary, inverse)
SELECT gen_random_uuid(), (SELECT id FROM u WHERE n = 1 + (g % 200)), 'user', 'episode', 's', '{}'
FROM generate_series(1, 200000) g;
INSERT INTO actions (id, user_id, actor, kind, summary, inverse)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-00000000beef', 'user', 'episode', 's', '{}'
FROM generate_series(1, 5000) g;

INSERT INTO points_events (id, user_id, kind, points, dedupe_root, seq, dedupe_key, local_date, time_zone, action_id)
SELECT gen_random_uuid(), a.user_id, 'episode', 10, a.id::text, 1, a.id::text, current_date, 'UTC', a.id FROM actions a;

INSERT INTO user_badges (id, user_id, badge, tier, awarded_at, origin, action_id)
SELECT gen_random_uuid(), a.user_id, 'b' || row_number() OVER (PARTITION BY a.user_id), 1, now(), 'live', a.id
FROM actions a WHERE random() < 0.05;

INSERT INTO agent_tokens (id, user_id, name, kind, token_hash, scopes)
SELECT gen_random_uuid(), id, 'Scrobbler', 'browser', md5(id::text), ARRAY['scrobble:write'] FROM users;

UPDATE listens l SET agent_token_id = t.id FROM agent_tokens t WHERE t.user_id = l.user_id AND l.source = 'live';

VACUUM ANALYZE;
