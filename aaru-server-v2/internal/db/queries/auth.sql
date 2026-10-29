-- name: SessionUserID :one
SELECT user_id FROM sessions WHERE token_hash = $1 AND expires_at > $2;

-- name: CountUsers :one
SELECT count(*) FROM users;
