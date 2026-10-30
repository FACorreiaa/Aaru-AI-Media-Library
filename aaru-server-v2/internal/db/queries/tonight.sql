-- PostgresTonightStore.swift: Tonight's reads and its two small tables (AG-005).

-- name: TonightReading :many
SELECT li.id AS item_id, sqlc.embed(t), li.book_page, li.book_percent, li.updated_at
FROM library_items li JOIN titles t ON t.id = li.title_id AND t.type = 'book'
WHERE li.user_id = sqlc.arg(user_id) AND li.status = 'in_progress'
ORDER BY li.updated_at DESC, li.id DESC
LIMIT sqlc.arg(max_rows);

-- name: TonightItemDates :many
SELECT id, added_at, updated_at FROM library_items
WHERE user_id = sqlc.arg(user_id) AND id = ANY(sqlc.arg(ids)::uuid[]);

-- name: TonightFeedbackSince :many
SELECT library_item_id, verdict, day::text AS day, created_at FROM tonight_feedback
WHERE user_id = sqlc.arg(user_id) AND created_at >= sqlc.arg(since)
ORDER BY created_at;

-- name: TonightSaveFeedback :many
-- Through library_items, so an item that is not the user's writes nothing.
INSERT INTO tonight_feedback (id, user_id, library_item_id, verdict, day, created_at)
SELECT sqlc.arg(id)::uuid, li.user_id, li.id, sqlc.arg(verdict)::text, sqlc.arg(day)::text::date,
    sqlc.arg(created_at)::timestamptz
FROM library_items li
WHERE li.id = sqlc.arg(library_item_id) AND li.user_id = sqlc.arg(user_id)
RETURNING id;

-- name: TonightClearFeedback :exec
DELETE FROM tonight_feedback
WHERE user_id = sqlc.arg(user_id) AND library_item_id = sqlc.arg(library_item_id)
  AND day = sqlc.arg(day)::text::date;

-- name: TonightShownOn :one
SELECT EXISTS (
    SELECT 1 FROM tonight_picks WHERE user_id = sqlc.arg(user_id) AND day = sqlc.arg(day)::text::date
) AS shown;

-- name: TonightRecordPick :exec
INSERT INTO tonight_picks (user_id, day, library_item_id, rank, served_at)
VALUES (sqlc.arg(user_id), sqlc.arg(day)::text::date, sqlc.arg(library_item_id), sqlc.arg(rank),
    sqlc.arg(served_at))
ON CONFLICT (user_id, day, library_item_id)
    DO UPDATE SET rank = EXCLUDED.rank, served_at = EXCLUDED.served_at;

-- name: TonightAcceptPicks :many
-- After a progress write on these items: marks picks shown in the last six hours as taken, and
-- returns the days on which this is the first pick taken (what tonight_accepted counts). The outer
-- SELECT reads the snapshot before the UPDATE: "already taken" means taken earlier.
WITH taken AS (
    UPDATE tonight_picks SET accepted_at = now()
    WHERE tonight_picks.user_id = sqlc.arg(user_id) AND library_item_id = ANY(sqlc.arg(ids)::uuid[])
      AND accepted_at IS NULL AND served_at > now() - interval '6 hours'
    RETURNING day
)
SELECT DISTINCT taken.day::text AS day FROM taken
WHERE NOT EXISTS (
    SELECT 1 FROM tonight_picks p
    WHERE p.user_id = sqlc.arg(user_id) AND p.day = taken.day AND p.accepted_at IS NOT NULL
);
