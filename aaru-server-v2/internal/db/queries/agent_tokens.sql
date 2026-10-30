-- Agent tokens (OUT-001, OUT-004): the scoped, revocable credentials outside callers use.

-- name: CreateAgentToken :exec
INSERT INTO agent_tokens (id, user_id, name, kind, token_hash, scopes, created_at)
VALUES (@id, @user_id, @name, @kind, @token_hash, @scopes::text[], @created_at);

-- Tokens not revoked, newest first.
-- name: ListAgentTokens :many
SELECT id, user_id, name, kind, scopes, created_at, last_used_at FROM agent_tokens
WHERE user_id = @user_id AND revoked_at IS NULL
ORDER BY created_at DESC;

-- A revoked token's waiting plans expire with it: nothing it asked for lands later.
-- name: RevokeAgentToken :one
WITH revoked AS (
    UPDATE agent_tokens SET revoked_at = @now::pg_catalog.timestamptz
    WHERE agent_tokens.id = @id AND agent_tokens.user_id = @user_id AND agent_tokens.revoked_at IS NULL
    RETURNING agent_tokens.id
), expired AS (
    UPDATE agent_plans SET status = 'expired', decided_at = @now::pg_catalog.timestamptz
    WHERE agent_plans.agent_token_id IN (SELECT revoked.id FROM revoked) AND agent_plans.status = 'pending'
)
SELECT revoked.id FROM revoked;

-- The live token with this hash; none when unknown, revoked or expired.
-- name: AgentTokenByHash :one
SELECT id, user_id, name, kind, scopes, created_at, last_used_at FROM agent_tokens
WHERE token_hash = @token_hash AND revoked_at IS NULL
  AND (expires_at IS NULL OR expires_at > @now::pg_catalog.timestamptz);

-- name: TouchAgentToken :exec
UPDATE agent_tokens SET last_used_at = @at::pg_catalog.timestamptz WHERE id = @id;
