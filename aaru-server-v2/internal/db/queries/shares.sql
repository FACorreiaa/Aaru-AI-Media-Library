-- SHR-002 share links (PostgresShareStore.swift): `shares`, one row per link.

-- name: ShareCreate :exec
INSERT INTO shares (code, sender_id, kind, title_id, sport_event_id, concert_id, note, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8);

-- name: ShareByCode :one
SELECT code, sender_id, kind, title_id, sport_event_id, concert_id, note, created_at
FROM shares WHERE code = $1;

-- name: ShareExisting :one
-- The sender's newest link to this target with exactly this note (nil matches nil).
SELECT code, sender_id, kind, title_id, sport_event_id, concert_id, note, created_at FROM shares
WHERE sender_id = sqlc.arg(sender_id)::uuid AND kind = sqlc.arg(kind)::text
  AND title_id IS NOT DISTINCT FROM sqlc.narg(title_id)::uuid
  AND sport_event_id IS NOT DISTINCT FROM sqlc.narg(sport_event_id)::text
  AND concert_id IS NOT DISTINCT FROM sqlc.narg(concert_id)::text
  AND note IS NOT DISTINCT FROM sqlc.narg(note)::text
ORDER BY created_at DESC LIMIT 1;
