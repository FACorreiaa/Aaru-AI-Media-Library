-- OAuth 2.1 front door for Claude's connector (OUT-004).

-- name: CreateOAuthClient :exec
INSERT INTO oauth_clients (id, name, redirect_uris, created_at)
VALUES (@id, @name, @redirect_uris::text[], @created_at);

-- name: OAuthClient :one
SELECT id, name, redirect_uris, created_at FROM oauth_clients WHERE id = @id;

-- name: CreateOAuthRequest :exec
INSERT INTO oauth_requests (id, client_id, redirect_uri, state, code_challenge, resource, binding_hash, expires_at)
VALUES (@id, @client_id, @redirect_uri, sqlc.narg('state'), @code_challenge, sqlc.narg('resource'), @binding_hash,
    @expires_at);

-- A request not yet answered and not expired.
-- name: OAuthRequest :one
SELECT id, client_id, redirect_uri, state, code_challenge, resource, binding_hash, expires_at FROM oauth_requests
WHERE id = @id AND consumed_at IS NULL AND expires_at > @now::pg_catalog.timestamptz;

-- name: ConsumeOAuthRequest :one
UPDATE oauth_requests SET consumed_at = @now::pg_catalog.timestamptz
WHERE id = @id AND consumed_at IS NULL AND expires_at > @now::pg_catalog.timestamptz
RETURNING id, client_id, redirect_uri, state, code_challenge, resource, binding_hash, expires_at;

-- name: CreateOAuthCode :exec
INSERT INTO oauth_codes (code_hash, client_id, user_id, redirect_uri, code_challenge, resource, name, kind,
    allow_writes, expires_at)
VALUES (@code_hash, @client_id, @user_id, @redirect_uri, @code_challenge, sqlc.narg('resource'), @name, @kind,
    @allow_writes, @expires_at);

-- name: OAuthCodeForUpdate :one
SELECT client_id, user_id, redirect_uri, code_challenge, resource, name, kind, allow_writes, expires_at,
    consumed_at, agent_token_id
FROM oauth_codes WHERE code_hash = @code_hash FOR UPDATE;

-- name: ConsumeOAuthCode :exec
UPDATE oauth_codes SET consumed_at = @now::pg_catalog.timestamptz WHERE code_hash = @code_hash;

-- name: CreateOAuthAgentToken :exec
INSERT INTO agent_tokens (id, user_id, name, kind, token_hash, scopes, created_at, expires_at, issuance,
    oauth_client_id)
VALUES (@id, @user_id, @name, @kind, @token_hash, @scopes::text[], @created_at, @@expires_at::pg_catalog.timestamptz, 'oauth', @client_id::text);

-- name: CreateOAuthRefreshToken :exec
INSERT INTO oauth_refresh_tokens (token_hash, agent_token_id, client_id, expires_at)
VALUES (@token_hash, @agent_token_id, @client_id, @expires_at);

-- name: LinkOAuthCodeToken :exec
UPDATE oauth_codes SET agent_token_id = @agent_token_id::uuid WHERE code_hash = @code_hash;

-- name: OAuthRefreshForUpdate :one
SELECT r.agent_token_id, r.client_id, r.expires_at, r.consumed_at, t.revoked_at, t.scopes
FROM oauth_refresh_tokens r JOIN agent_tokens t ON t.id = r.agent_token_id
WHERE r.token_hash = @token_hash FOR UPDATE;

-- name: ConsumeOAuthRefresh :exec
UPDATE oauth_refresh_tokens SET consumed_at = @now::pg_catalog.timestamptz WHERE token_hash = @token_hash;

-- name: RotateOAuthAccess :exec
UPDATE agent_tokens SET token_hash = @token_hash, expires_at = @expires_at::pg_catalog.timestamptz WHERE id = @id;

-- The connection an access or refresh token belongs to.
-- name: OAuthConnectionForToken :one
SELECT t.id FROM agent_tokens t WHERE t.issuance = 'oauth' AND (t.token_hash = @token_hash::text OR t.id IN (
    SELECT r.agent_token_id FROM oauth_refresh_tokens r WHERE r.token_hash = @token_hash::text
)) LIMIT 1;

-- As Settings' revoke does: the token stops at once.
-- name: RevokeAgentTokenByID :exec
UPDATE agent_tokens SET revoked_at = @now::pg_catalog.timestamptz WHERE id = @id AND revoked_at IS NULL;

-- ...and its waiting plans expire with it.
-- name: ExpireAgentTokenPlans :exec
UPDATE agent_plans SET status = 'expired', decided_at = @now::pg_catalog.timestamptz
WHERE agent_token_id = @agent_token_id::uuid AND status = 'pending';
