-- SCR-001/007/008/009 · watch events, plays and the "Now playing" Live Activity
-- (PostgresWatchEventStore.swift).

-- name: RecordWatchEvent :one
-- Opens or updates the session for this user, source and item.
INSERT INTO watch_events
    (id, user_id, agent_token_id, source, external_ref, title_id, season, episode, state,
     position_ms, duration_ms, started_at, updated_at)
VALUES (sqlc.arg(id)::uuid, sqlc.arg(user_id)::uuid, sqlc.narg(agent_token_id)::uuid, sqlc.arg(source)::text,
        sqlc.arg(external_ref)::text, sqlc.narg(title_id)::uuid, sqlc.narg(season)::int, sqlc.narg(episode)::int,
        sqlc.arg(state)::text, sqlc.arg(position_ms)::bigint, sqlc.arg(duration_ms)::bigint,
        sqlc.arg(now)::timestamptz, sqlc.arg(now)::timestamptz)
ON CONFLICT (user_id, source, external_ref) WHERE stopped_at IS NULL DO UPDATE SET
    state = EXCLUDED.state,
    position_ms = EXCLUDED.position_ms,
    duration_ms = greatest(watch_events.duration_ms, EXCLUDED.duration_ms),
    title_id = coalesce(EXCLUDED.title_id, watch_events.title_id),
    updated_at = EXCLUDED.updated_at
RETURNING id, title_id, position_ms, duration_ms;

-- name: CloseWatchEvent :exec
UPDATE watch_events SET stopped_at = sqlc.arg(at)::timestamptz, state = 'stopped', updated_at = sqlc.arg(at)::timestamptz
WHERE id = sqlc.arg(id)::uuid;

-- name: StoppedRecently :one
-- Whether a session for this item was closed since `since`: a second `stop` is a repeat.
SELECT EXISTS (
    SELECT 1 FROM watch_events
    WHERE user_id = sqlc.arg(user_id)::uuid AND source = sqlc.arg(source)::text
      AND external_ref = sqlc.arg(external_ref)::text AND stopped_at >= sqlc.arg(since)::timestamptz
)::bool;

-- name: OpenWatchEvents :many
-- The user's open, matched sessions, newest report first; only `source`'s when given.
SELECT we.id, we.source, we.external_ref, we.title_id AS title_id, li.id AS item_id, we.season, we.episode,
    se.name AS episode_name, se.runtime_minutes AS episode_runtime, t.runtime_minutes AS title_runtime,
    we.state, we.position_ms, we.duration_ms, we.updated_at
FROM watch_events we
JOIN titles t ON t.id = we.title_id
LEFT JOIN library_items li ON li.user_id = we.user_id AND li.title_id = we.title_id
LEFT JOIN show_episodes se ON se.title_id = we.title_id AND se.season = we.season
    AND se.episode = we.episode
WHERE we.user_id = sqlc.arg(user_id)::uuid AND we.stopped_at IS NULL
  AND (sqlc.narg(source)::text IS NULL OR we.source = sqlc.narg(source)::text)
ORDER BY we.updated_at DESC
LIMIT sqlc.arg(max_rows)::int;

-- name: RegisterLiveActivityToken :exec
-- A token belongs to one user: registering it again moves it.
INSERT INTO live_activity_tokens (token, user_id, kind, environment, topic, updated_at)
VALUES (sqlc.arg(token)::text, sqlc.arg(user_id)::uuid, sqlc.arg(kind)::text, sqlc.arg(environment)::text,
        sqlc.arg(topic)::text, sqlc.arg(now)::timestamptz)
ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, kind = EXCLUDED.kind,
    environment = EXCLUDED.environment, topic = EXCLUDED.topic, updated_at = EXCLUDED.updated_at;

-- name: HasLiveActivityTokens :one
SELECT EXISTS (SELECT 1 FROM live_activity_tokens WHERE user_id = sqlc.arg(user_id)::uuid)::bool;

-- name: LiveActivityTokens :many
SELECT token, kind, environment, topic FROM live_activity_tokens
WHERE user_id = sqlc.arg(user_id)::uuid AND kind = sqlc.arg(kind)::text;

-- name: ForgetLiveActivityToken :exec
DELETE FROM live_activity_tokens WHERE token = sqlc.arg(token)::text;

-- name: ForgetLiveActivityUpdates :exec
DELETE FROM live_activity_tokens WHERE user_id = sqlc.arg(user_id)::uuid AND kind = 'update';

-- name: SaveLivePlay :exec
-- Replaces the connection's last play of that kind. The same `ref` again keeps the row's id and start,
-- so the activity hears no change.
INSERT INTO live_plays
    (user_id, agent_token_id, kind, id, source, ref, title, subtitle, service, artwork_url, origin_url,
     state, position_ms, duration_ms, started_at, updated_at, expires_at)
VALUES (sqlc.arg(user_id)::uuid, sqlc.arg(agent_token_id)::uuid, sqlc.arg(kind)::text, sqlc.arg(id)::uuid,
        sqlc.arg(source)::text, sqlc.arg(ref)::text, sqlc.arg(title)::text, sqlc.narg(subtitle)::text,
        sqlc.narg(service)::text, sqlc.narg(artwork_url)::text, sqlc.narg(origin_url)::text,
        sqlc.arg(state)::text, sqlc.arg(position_ms)::bigint, sqlc.arg(duration_ms)::bigint,
        sqlc.arg(started_at)::timestamptz, sqlc.arg(updated_at)::timestamptz, sqlc.arg(expires_at)::timestamptz)
ON CONFLICT (user_id, kind, agent_token_id) DO UPDATE SET
    id = CASE WHEN live_plays.ref = EXCLUDED.ref THEN live_plays.id ELSE EXCLUDED.id END,
    started_at = CASE WHEN live_plays.ref = EXCLUDED.ref THEN live_plays.started_at
        ELSE EXCLUDED.started_at END,
    source = EXCLUDED.source, ref = EXCLUDED.ref, title = EXCLUDED.title, subtitle = EXCLUDED.subtitle,
    service = EXCLUDED.service, artwork_url = EXCLUDED.artwork_url, origin_url = EXCLUDED.origin_url,
    state = EXCLUDED.state, position_ms = EXCLUDED.position_ms, duration_ms = EXCLUDED.duration_ms,
    updated_at = EXCLUDED.updated_at, expires_at = EXCLUDED.expires_at;

-- name: RemoveLivePlay :exec
DELETE FROM live_plays WHERE user_id = sqlc.arg(user_id)::uuid AND kind = sqlc.arg(kind)::text
    AND agent_token_id = sqlc.arg(agent_token_id)::uuid;

-- name: DeleteExpiredLivePlays :exec
DELETE FROM live_plays WHERE user_id = sqlc.arg(user_id)::uuid AND expires_at <= sqlc.arg(now)::timestamptz;

-- name: LivePlays :many
SELECT id, kind, source, ref, title, subtitle, service, artwork_url, origin_url, state, position_ms,
    duration_ms, started_at, updated_at, expires_at
FROM live_plays WHERE user_id = sqlc.arg(user_id)::uuid
ORDER BY updated_at DESC;

-- name: EnsureLiveActivityState :exec
INSERT INTO live_activity_states (user_id) VALUES (sqlc.arg(user_id)::uuid) ON CONFLICT DO NOTHING;

-- name: LiveActivityState :one
SELECT pushed, lingering, version, next_check_at FROM live_activity_states WHERE user_id = sqlc.arg(user_id)::uuid;

-- name: SaveLiveActivityState :execrows
-- Saves the state if no one saved since it was read (its version).
UPDATE live_activity_states SET pushed = sqlc.narg(pushed)::jsonb, lingering = sqlc.arg(lingering)::jsonb,
    version = version + 1, next_check_at = sqlc.narg(next_check_at)::timestamptz
WHERE user_id = sqlc.arg(user_id)::uuid AND version = sqlc.arg(version)::int;

-- name: ScheduleLiveActivityCheck :exec
-- The sweep looks at the user again at `at`, unless it already will sooner.
UPDATE live_activity_states SET next_check_at = sqlc.arg(at)::timestamptz
WHERE user_id = sqlc.arg(user_id)::uuid AND (next_check_at IS NULL OR next_check_at > sqlc.arg(at)::timestamptz);

-- name: ClaimDueLiveActivityChecks :many
-- Claims the users whose check is due, so one sweep alone looks at each.
UPDATE live_activity_states SET next_check_at = NULL
WHERE user_id IN (
    SELECT s.user_id FROM live_activity_states s WHERE s.next_check_at <= sqlc.arg(now)::timestamptz
    ORDER BY s.next_check_at LIMIT sqlc.arg(max_rows)::int FOR UPDATE SKIP LOCKED
)
RETURNING user_id;
