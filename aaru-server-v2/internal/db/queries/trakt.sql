-- Trakt connect (IMP-002): PKCE sign-ins in flight and one sealed connection per user
-- (PostgresTraktStore).

-- name: TraktCreateAuthRequest :exec
INSERT INTO trakt_auth_requests (state_hash, user_id, code_verifier, return_to, expires_at)
VALUES (@state_hash, @user_id, @code_verifier, @return_to, @expires_at);

-- One statement: a replayed callback finds nothing.
-- name: TraktConsumeAuthRequest :many
DELETE FROM trakt_auth_requests WHERE state_hash = @state_hash
RETURNING user_id, code_verifier, return_to, expires_at;

-- name: TraktSaveConnection :exec
INSERT INTO trakt_connections (user_id, access_token, refresh_token, expires_at, username, connected_at)
VALUES (@user_id, @access_token, @refresh_token, @expires_at, sqlc.narg('username'), @connected_at)
ON CONFLICT (user_id) DO UPDATE SET access_token = EXCLUDED.access_token,
    refresh_token = EXCLUDED.refresh_token, expires_at = EXCLUDED.expires_at,
    username = COALESCE(EXCLUDED.username, trakt_connections.username);

-- name: TraktConnection :many
SELECT access_token, refresh_token, expires_at, username, connected_at FROM trakt_connections
WHERE user_id = @user_id;

-- name: TraktConnectionForUpdate :many
SELECT access_token, refresh_token, expires_at, username, connected_at FROM trakt_connections
WHERE user_id = @user_id FOR UPDATE;

-- name: TraktUpdateTokens :exec
UPDATE trakt_connections SET access_token = @access_token, refresh_token = @refresh_token,
    expires_at = @expires_at
WHERE user_id = @user_id;

-- name: TraktDeleteConnection :exec
DELETE FROM trakt_connections WHERE user_id = @user_id;
