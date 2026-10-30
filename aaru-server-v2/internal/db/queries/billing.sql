-- PostgresEntitlementStore.swift: App Store subscriptions (BIL-001). A write never replaces a
-- state Apple signed later.

-- name: RecordEntitlement :many
INSERT INTO entitlements (original_transaction_id, user_id, product_id, environment, expires_at, revoked_at,
                          signed_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
ON CONFLICT (original_transaction_id) DO UPDATE SET
    product_id = EXCLUDED.product_id, environment = EXCLUDED.environment,
    expires_at = EXCLUDED.expires_at, revoked_at = EXCLUDED.revoked_at,
    signed_at = EXCLUDED.signed_at, updated_at = EXCLUDED.updated_at
WHERE entitlements.signed_at <= EXCLUDED.signed_at
RETURNING (xmax = 0)::boolean AS inserted;

-- name: ActiveEntitlement :many
SELECT original_transaction_id, product_id, environment, expires_at, signed_at FROM entitlements
WHERE user_id = sqlc.arg(user_id) AND revoked_at IS NULL
  AND (expires_at IS NULL OR expires_at > sqlc.arg(now))
ORDER BY expires_at DESC NULLS FIRST
LIMIT 1;

-- name: EntitlementOwner :many
SELECT user_id FROM entitlements WHERE original_transaction_id = $1;

-- name: BillingUserExists :one
SELECT EXISTS (SELECT 1 FROM users WHERE id = $1);

-- name: BillingCapturesSince :one
-- PostgresCaptureStore.captures: what the entitlement reports as this month's captures.
SELECT count(*)::int AS count FROM import_jobs
WHERE user_id = $1 AND source = 'capture' AND created_at >= $2;
