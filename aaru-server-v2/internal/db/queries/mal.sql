-- MyAnimeList connect, push and read-back (SCR-005, SCR-010; PostgresMALStore).

-- name: MALCreateAuthRequest :exec
INSERT INTO mal_auth_requests (state_hash, user_id, code_verifier, return_to, expires_at)
VALUES (@state_hash, @user_id, @code_verifier, @return_to, @expires_at);

-- One statement: a replayed callback finds nothing.
-- name: MALConsumeAuthRequest :many
DELETE FROM mal_auth_requests WHERE state_hash = @state_hash
RETURNING user_id, code_verifier, return_to, expires_at;

-- name: MALSaveConnection :exec
INSERT INTO mal_connections
    (user_id, access_token, refresh_token, expires_at, username, connected_at, push_cursor)
VALUES (@user_id, @access_token, @refresh_token, @expires_at, sqlc.narg('username'), @connected_at, @push_cursor)
ON CONFLICT (user_id) DO UPDATE SET access_token = EXCLUDED.access_token,
    refresh_token = EXCLUDED.refresh_token, expires_at = EXCLUDED.expires_at,
    username = COALESCE(EXCLUDED.username, mal_connections.username), revoked_at = NULL;

-- name: MALConnection :many
SELECT access_token, refresh_token, expires_at, username, connected_at, revoked_at, pulled_at
FROM mal_connections WHERE user_id = @user_id;

-- name: MALConnectionForUpdate :many
SELECT access_token, refresh_token, expires_at, username, connected_at, revoked_at, pulled_at
FROM mal_connections WHERE user_id = @user_id FOR UPDATE;

-- name: MALUpdateTokens :exec
UPDATE mal_connections SET access_token = @access_token, refresh_token = @refresh_token,
    expires_at = @expires_at
WHERE user_id = @user_id;

-- name: MALDeleteEntryStates :exec
DELETE FROM mal_entry_states WHERE user_id = @user_id;

-- name: MALDeleteConnection :exec
DELETE FROM mal_connections WHERE user_id = @user_id;

-- name: MALMarkRevoked :exec
UPDATE mal_connections SET revoked_at = @revoked_at WHERE user_id = @user_id;

-- name: MALPushesDue :many
SELECT c.user_id, c.push_cursor FROM mal_connections c
WHERE c.revoked_at IS NULL AND EXISTS (
    SELECT 1 FROM library_items li WHERE li.user_id = c.user_id AND li.updated_at > c.push_cursor
);

-- name: MALAdvanceCursor :exec
UPDATE mal_connections SET push_cursor = GREATEST(push_cursor, @cursor::pg_catalog.timestamptz)
WHERE user_id = @user_id;

-- name: MALEntryStates :many
SELECT mal_id, status, episodes, score FROM mal_entry_states
WHERE user_id = @user_id AND mal_id = ANY(@mal_ids::text[]);

-- name: MALSaveEntryState :exec
INSERT INTO mal_entry_states (user_id, mal_id, status, episodes, score, title, updated_at)
VALUES (@user_id, @mal_id, @status, @episodes, @score, sqlc.narg('title'), now())
ON CONFLICT (user_id, mal_id) DO UPDATE SET status = EXCLUDED.status, episodes = EXCLUDED.episodes,
    score = EXCLUDED.score, title = COALESCE(EXCLUDED.title, mal_entry_states.title),
    removed_at = NULL, updated_at = now();

-- name: MALRequestPull :many
UPDATE mal_connections SET pull_requested_at = @now::pg_catalog.timestamptz
WHERE user_id = @user_id AND revoked_at IS NULL
    AND (pulled_at IS NULL OR pulled_at < @not_before::pg_catalog.timestamptz)
RETURNING user_id;

-- Asked-for reads first; SKIP LOCKED keeps two replicas off the same connection.
-- name: MALClaimPulls :many
UPDATE mal_connections c SET pulled_at = @now::pg_catalog.timestamptz, pull_requested_at = NULL
WHERE c.user_id IN (
    SELECT m.user_id FROM mal_connections m
    WHERE m.revoked_at IS NULL
        AND (m.pull_requested_at IS NOT NULL OR m.pulled_at IS NULL
            OR m.pulled_at < @stale_before::pg_catalog.timestamptz)
    ORDER BY m.pull_requested_at NULLS LAST, m.pulled_at NULLS FIRST
    LIMIT @max_rows
    FOR UPDATE SKIP LOCKED
)
RETURNING c.user_id, COALESCE(c.pull_cursor, c.connected_at)::pg_catalog.timestamptz AS cursor,
    (c.full_read_at IS NULL OR c.full_read_at < @full_before::pg_catalog.timestamptz)::boolean AS full_read;

-- name: MALFinishPull :exec
UPDATE mal_connections
SET pull_cursor = GREATEST(COALESCE(pull_cursor, connected_at), @cursor::pg_catalog.timestamptz),
    full_read_at = COALESCE(sqlc.narg('full_read_at')::pg_catalog.timestamptz, full_read_at)
WHERE user_id = @user_id;

-- name: MALMarkRemoved :exec
UPDATE mal_entry_states SET removed_at = CASE
    WHEN mal_id = ANY(@listed::text[]) THEN NULL ELSE COALESCE(removed_at, @now::pg_catalog.timestamptz) END
WHERE user_id = @user_id;

-- name: MALRemovedEntries :many
SELECT mal_id, title, removed_at::pg_catalog.timestamptz AS removed_at FROM mal_entry_states
WHERE user_id = @user_id AND removed_at IS NOT NULL
ORDER BY removed_at DESC, title LIMIT 100;
