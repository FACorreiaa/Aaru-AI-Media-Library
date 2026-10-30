-- Agent plans (AG-003, OUT-004): changes an outside agent asked for that wait for the user
-- (PostgresPlanStore).

-- name: PlanCreate :exec
INSERT INTO agent_plans (id, user_id, agent_token_id, agent_name, status, summary, changes, counts, op, basis,
    created_at, expires_at)
VALUES (@id, @user_id, sqlc.narg('agent_token_id')::uuid, @agent_name, @status, @summary, @changes, @counts, @op,
    @basis, @created_at::pg_catalog.timestamptz, @expires_at::pg_catalog.timestamptz);

-- Pending plans not yet expired, newest first.
-- name: PlansPending :many
SELECT id, agent_token_id, agent_name, status, summary, changes, counts, op, basis, created_at, expires_at,
    decided_at, action_id
FROM agent_plans
WHERE user_id = @user_id AND status = 'pending' AND expires_at > @now::pg_catalog.timestamptz
ORDER BY created_at DESC LIMIT @row_limit;

-- name: PlansAll :many
SELECT id, agent_token_id, agent_name, status, summary, changes, counts, op, basis, created_at, expires_at,
    decided_at, action_id
FROM agent_plans
WHERE user_id = @user_id
ORDER BY created_at DESC LIMIT @row_limit;

-- name: PlanByID :one
SELECT id, agent_token_id, agent_name, status, summary, changes, counts, op, basis, created_at, expires_at,
    decided_at, action_id
FROM agent_plans
WHERE id = @id AND user_id = @user_id;

-- name: PlanLock :one
SELECT id, agent_token_id, agent_name, status, summary, changes, counts, op, basis, created_at, expires_at,
    decided_at, action_id
FROM agent_plans
WHERE id = @id AND user_id = @user_id FOR UPDATE;

-- Plans this token has waiting, so one agent cannot flood the user.
-- name: PlanPendingCount :one
SELECT count(*)::int AS count FROM agent_plans
WHERE agent_token_id = @agent_token_id AND status = 'pending' AND expires_at > @now::pg_catalog.timestamptz;

-- name: PlanDecide :exec
UPDATE agent_plans SET status = @status, decided_at = @decided_at::pg_catalog.timestamptz,
    action_id = sqlc.narg('action_id')::uuid
WHERE id = @id;

-- Each item's updated_at in microseconds, for a plan's basis.
-- name: PlanItemVersions :many
SELECT id, (extract(epoch FROM updated_at) * 1000000)::bigint AS micros FROM library_items
WHERE user_id = @user_id AND id = ANY(@ids::uuid[]);

-- name: PlanItemVersionsLocked :many
SELECT id, (extract(epoch FROM updated_at) * 1000000)::bigint AS micros FROM library_items
WHERE user_id = @user_id AND id = ANY(@ids::uuid[])
FOR UPDATE;

-- Whether any of these titles is in the user's library.
-- name: PlanAnyTitlePresent :one
SELECT EXISTS (
    SELECT 1 FROM library_items WHERE user_id = @user_id AND title_id = ANY(@title_ids::uuid[])
) AS present;
