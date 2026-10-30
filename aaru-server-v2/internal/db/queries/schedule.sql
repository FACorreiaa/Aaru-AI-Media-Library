-- PostgresScheduleStore.swift: calendar (CAL-001) and Up Next (UPN-001, UPN-002). Each is one
-- query: no per-show round trips. "Aired" is library progress's rule (PROG-003): aired before now,
-- or undated in an ended or canceled show. Unfinished (a LEFT JOIN LATERAL) is in schedule/store.go.

-- name: ScheduleCalendar :many
SELECT li.id AS item_id, sqlc.embed(t), se.season, se.episode, se.name, se.airs_at, se.airs_at_exact,
    se.overview, se.runtime_minutes, se.still_url,
    (EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
             AND ep.season = se.season AND ep.episode = se.episode))::boolean AS watched,
    (SELECT max(s2.episode) FROM show_episodes s2 WHERE s2.title_id = se.title_id AND s2.season = se.season)::int
        AS season_last
FROM library_items li
JOIN titles t ON t.id = li.title_id AND t.type = 'show'
JOIN show_episodes se ON se.title_id = li.title_id
WHERE li.user_id = sqlc.arg(user_id) AND li.status IN ('wishlist', 'in_progress')
  AND se.airs_at >= sqlc.arg(from_time) AND se.airs_at < sqlc.arg(until_time)
ORDER BY se.airs_at, t.title, se.season, se.episode;

-- name: ScheduleContinueWatching :many
SELECT li.id AS item_id, sqlc.embed(t),
    nxt.season AS next_season, nxt.episode AS next_episode, nxt.name AS next_name,
    coalesce(nxt.runtime_minutes, t.runtime_minutes) AS next_runtime,
    rem.count AS remaining_count, rem.minutes AS remaining_minutes,
    (nxt.episode = (SELECT max(s2.episode) FROM show_episodes s2
                    WHERE s2.title_id = li.title_id AND s2.season = nxt.season))::boolean AS is_finale
FROM library_items li
JOIN titles t ON t.id = li.title_id AND t.type = 'show'
JOIN LATERAL (
    SELECT se.season, se.episode, se.name, se.runtime_minutes FROM show_episodes se
    WHERE se.title_id = li.title_id AND se.season > 0
      AND (se.airs_at <= sqlc.arg(now) OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')))
      AND NOT EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
                      AND ep.season = se.season AND ep.episode = se.episode)
    ORDER BY se.season, se.episode LIMIT 1
) nxt ON true
JOIN LATERAL (
    SELECT count(*)::int AS count,
        coalesce(sum(coalesce(se.runtime_minutes, t.runtime_minutes, 0)), 0)::int AS minutes
    FROM show_episodes se
    WHERE se.title_id = li.title_id AND se.season > 0
      AND (se.airs_at <= sqlc.arg(now) OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')))
      AND NOT EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
                      AND ep.season = se.season AND ep.episode = se.episode)
) rem ON true
WHERE li.user_id = sqlc.arg(user_id) AND li.status = 'in_progress'
ORDER BY li.updated_at DESC, li.id DESC
LIMIT sqlc.arg(max_rows);

-- name: ScheduleStartWatching :many
SELECT li.id AS item_id, sqlc.embed(t)
FROM library_items li JOIN titles t ON t.id = li.title_id
WHERE li.user_id = sqlc.arg(user_id) AND li.status = 'wishlist'
ORDER BY li.added_at DESC, li.id DESC
LIMIT sqlc.arg(max_rows);

-- name: ScheduleLibraryCounts :many
SELECT status, count(*)::int AS count FROM library_items
WHERE user_id = $1 GROUP BY status;

-- name: SchedulePendingShowCount :one
SELECT count(*)::int AS count FROM library_items li JOIN titles t ON t.id = li.title_id
WHERE li.user_id = $1 AND li.status IN ('wishlist', 'in_progress')
  AND t.type = 'show' AND t.episodes_hydrated_at IS NULL AND t.episodes_attempted_at IS NULL;
