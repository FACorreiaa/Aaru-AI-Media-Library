-- name: WorldByKeys :many
-- The Worlds any of these node keys belong to, oldest first (GRAPH-007). More than one only
-- while two Worlds that turned out to be the same have not been merged yet.
SELECT DISTINCT w.id, w.root_key, w.name, w.links, w.truncated, w.partial, w.title_count, w.built_at, w.created_at
FROM world_keys k
JOIN worlds w ON w.id = k.world_id
WHERE k.node_key = ANY(sqlc.arg(node_keys)::text[])
ORDER BY w.created_at, w.id;

-- name: WorldTitles :many
SELECT "position", node_key, lane, lane_position, side, node FROM world_titles
WHERE world_id = @world_id
ORDER BY "position";

-- name: WorldTitleByKey :one
-- One title of a World by its first key: the root, to start a rebuild from.
SELECT node FROM world_titles WHERE world_id = @world_id AND node_key = @node_key;

-- name: PutWorld :exec
INSERT INTO worlds (id, root_key, name, links, truncated, partial, title_count, built_at, created_at)
VALUES (@id, @root_key, @name, @links, @truncated, @partial, @title_count, @built_at, @built_at)
ON CONFLICT (id) DO UPDATE SET root_key = EXCLUDED.root_key, name = EXCLUDED.name, links = EXCLUDED.links,
    truncated = EXCLUDED.truncated, partial = EXCLUDED.partial, title_count = EXCLUDED.title_count,
    built_at = EXCLUDED.built_at;

-- name: DeleteWorlds :exec
-- Worlds merged into another, and one whose root moved to a key another row holds.
DELETE FROM worlds WHERE id = ANY(sqlc.arg(ids)::uuid[]) OR (root_key = @root_key AND id <> @keep);

-- name: ClearWorldMembers :exec
DELETE FROM world_titles WHERE world_id = @world_id;

-- name: ClearWorldKeys :exec
-- A World's own keys, and any of the new keys another World still holds.
DELETE FROM world_keys WHERE world_id = @world_id OR node_key = ANY(sqlc.arg(node_keys)::text[]);

-- name: PutWorldTitles :exec
INSERT INTO world_titles (world_id, "position", node_key, lane, lane_position, side, node)
SELECT @world_id::uuid, unnest(sqlc.arg(positions)::integer[]), unnest(sqlc.arg(node_keys)::text[]),
    unnest(sqlc.arg(lanes)::text[]), unnest(sqlc.arg(lane_positions)::integer[]), unnest(sqlc.arg(sides)::boolean[]),
    unnest(sqlc.arg(nodes)::jsonb[]);

-- name: PutWorldKeys :exec
INSERT INTO world_keys (node_key, world_id, "position")
SELECT unnest(sqlc.arg(node_keys)::text[]), @world_id::uuid, unnest(sqlc.arg(positions)::integer[]);

-- name: WorldBuild :one
SELECT title_id, priority, state, attempts, run_after, leased_until, checked_at FROM world_builds WHERE title_id = @title_id;

-- name: EnqueueWorldBuild :exec
-- Asks for a title's World to be built. A title already queued only gains priority; one being
-- built is left alone; one looked at before is queued again only once that look is older than
-- `stale_before` (a title with no World is asked about again after a while, never on every read).
INSERT INTO world_builds (title_id, priority, state, attempts, run_after, created_at)
VALUES (@title_id, @priority, 'queued', 0, @now, @now)
ON CONFLICT (title_id) DO UPDATE SET
    priority = greatest(world_builds.priority, EXCLUDED.priority),
    state = CASE WHEN world_builds.state IN ('done', 'failed') THEN 'queued' ELSE world_builds.state END,
    attempts = CASE WHEN world_builds.state IN ('done', 'failed') THEN 0 ELSE world_builds.attempts END,
    run_after = CASE WHEN world_builds.state IN ('done', 'failed') THEN EXCLUDED.run_after ELSE world_builds.run_after END
WHERE world_builds.state = 'queued'
   OR (world_builds.state IN ('done', 'failed')
       AND (world_builds.checked_at IS NULL OR world_builds.checked_at < sqlc.arg(stale_before)::timestamptz));

-- name: EnqueueWorldBuildsForUser :execrows
-- Every title in the user's library that was never looked at, at low priority: after an import,
-- so its Worlds are built behind the titles people open (GRAPH-007).
INSERT INTO world_builds (title_id, priority, state, attempts, run_after, created_at)
SELECT DISTINCT li.title_id, @priority::integer, 'queued', 0, sqlc.arg(now)::timestamptz, sqlc.arg(now)::timestamptz
FROM library_items li
WHERE li.user_id = @user_id
ON CONFLICT (title_id) DO NOTHING;

-- name: WorldBuildClaim :one
-- One statement: SKIP LOCKED means two workers never lease the same title. Highest priority
-- first, then the longest waiting. An expired lease is taken over while attempts are left
-- (WorldBuildFailExpired ends the rest).
UPDATE world_builds SET state = 'running', attempts = attempts + 1, leased_until = @leased_until
WHERE title_id = (
    SELECT b.title_id FROM world_builds b
    WHERE (b.state = 'queued' AND b.run_after <= @now)
       OR (b.state = 'running' AND b.leased_until < @now AND b.attempts < @max_attempts)
    ORDER BY b.priority DESC, b.run_after
    FOR UPDATE SKIP LOCKED
    LIMIT 1
)
RETURNING title_id, priority, attempts;

-- name: WorldBuildFailExpired :execrows
-- A build whose lease ran out on its last attempt: the process died under it. It ends as failed
-- instead of being leased again forever.
UPDATE world_builds SET state = 'failed', leased_until = NULL, checked_at = @now
WHERE state = 'running' AND leased_until < @now AND attempts >= @max_attempts;

-- name: WorldBuildDone :exec
UPDATE world_builds SET state = 'done', leased_until = NULL, checked_at = @now, priority = 0
WHERE title_id = @title_id;

-- name: WorldBuildRetry :exec
-- Back in the queue for later; a build out of attempts ends as failed.
UPDATE world_builds SET
    state = CASE WHEN attempts >= @max_attempts THEN 'failed' ELSE 'queued' END,
    leased_until = NULL, run_after = @run_after, checked_at = @now
WHERE title_id = @title_id;

-- name: WorldKeyPosition :one
-- Where in the World the title carrying any of these keys sits; the earliest when several do.
SELECT "position" FROM world_keys
WHERE world_id = @world_id AND node_key = ANY(sqlc.arg(node_keys)::text[])
ORDER BY "position"
LIMIT 1;

-- name: UserWorlds :many
-- The Worlds the user has at least one library item in (GRAPH-007), with one of their titles in
-- each to open it from. The key expressions are catalog.NodeKeys written in SQL, for the ids a
-- `titles` row holds; world_parity_test.go keeps the two the same.
SELECT w.id, w.root_key, w.name, w.links, w.truncated, w.partial, w.title_count, w.built_at, w.created_at,
    (array_agg(li.title_id ORDER BY k."position", li.title_id))[1]::uuid AS title_id
FROM library_items li
JOIN titles t ON t.id = li.title_id
CROSS JOIN LATERAL (VALUES
    ('anilist:' || t.anilist),
    ('mal:' || CASE WHEN t.type = 'manga' THEN 'manga' ELSE 'anime' END || ':' || t.mal),
    (CASE WHEN t.type IN ('movie', 'show') THEN 'tmdb:' || t.type || ':' || t.tmdb END),
    ('imdb:' || t.imdb),
    ('openlibrary:' || t.open_library),
    ('musicbrainz:' || t.musicbrainz)
) AS own(node_key)
JOIN world_keys k ON k.node_key = own.node_key
JOIN worlds w ON w.id = k.world_id
WHERE li.user_id = @user_id
GROUP BY w.id
ORDER BY w.built_at DESC, w.id
LIMIT sqlc.arg(max_worlds)::integer;

-- name: WorldTitlesOfWorlds :many
SELECT world_id, "position", node_key, lane, lane_position, side, node FROM world_titles
WHERE world_id = ANY(sqlc.arg(world_ids)::uuid[])
ORDER BY world_id, "position";
