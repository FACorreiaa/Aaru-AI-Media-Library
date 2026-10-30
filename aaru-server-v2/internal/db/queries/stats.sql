-- PostgresStatsStore.swift: period activity (GAM-006a) and the profile's library rows (GAM-006b).

-- name: StatsActivity :many
-- A finish at exactly 00:00 UTC is a date-only import (Letterboxd, Goodreads, MAL): that day is
-- the day, in every time zone. The day filter needs the zone, so it cannot use an index; the
-- instants bound the same days a day wider on each side (no zone is more than 14 hours off UTC),
-- so the episode ticks are read through `episode_progress_item_watched` for the period only.
WITH activity AS (
    SELECT li.title_id, t.type, t.is_anime, t.genres, li.rating, ep.watched_at AS at,
        (ep.watched_at AT TIME ZONE sqlc.arg(zone)::text)::date AS day,
        1 AS episodes, coalesce(se.runtime_minutes, t.runtime_minutes, 0) AS minutes, false AS finished
    FROM episode_progress ep
    JOIN library_items li ON li.id = ep.library_item_id
    JOIN titles t ON t.id = li.title_id
    LEFT JOIN show_episodes se ON se.title_id = li.title_id
        AND se.season = ep.season AND se.episode = ep.episode
    WHERE li.user_id = sqlc.arg(user_id) AND ep.watched_at_known
      AND ep.watched_at >= ((sqlc.arg(from_day)::text)::date - 1)::timestamp AT TIME ZONE 'UTC'
      AND ep.watched_at < ((sqlc.arg(until_day)::text)::date + 1)::timestamp AT TIME ZONE 'UTC'
    UNION ALL
    SELECT li.title_id, t.type, t.is_anime, t.genres, li.rating, li.finished_at AS at,
        CASE WHEN li.finished_at AT TIME ZONE 'UTC' = date_trunc('day', li.finished_at AT TIME ZONE 'UTC')
            THEN (li.finished_at AT TIME ZONE 'UTC')::date
            ELSE (li.finished_at AT TIME ZONE sqlc.arg(zone)::text)::date END AS day,
        0 AS episodes, CASE WHEN t.type = 'movie' THEN coalesce(t.runtime_minutes, 0) ELSE 0 END AS minutes,
        true AS finished
    FROM library_items li JOIN titles t ON t.id = li.title_id
    WHERE li.user_id = sqlc.arg(user_id) AND li.status = 'finished' AND li.finished_at IS NOT NULL
      AND li.finished_at >= ((sqlc.arg(from_day)::text)::date - 1)::timestamp AT TIME ZONE 'UTC'
      AND li.finished_at < ((sqlc.arg(until_day)::text)::date + 1)::timestamp AT TIME ZONE 'UTC'
)
SELECT day::text AS day, title_id, type, is_anime, genres, rating,
    sum(episodes)::int AS episodes, sum(minutes)::int AS minutes, bool_or(finished)::boolean AS finished,
    min(at)::timestamptz AS first_at, max(at)::timestamptz AS last_at
FROM activity
WHERE day >= (sqlc.arg(from_day)::text)::date AND day < (sqlc.arg(until_day)::text)::date
GROUP BY day, title_id, type, is_anime, genres, rating
ORDER BY day, first_at;

-- name: StatsProfileLibrary :many
-- Every item with all its ticks, dated or not: the profile is the library's state.
SELECT li.title_id, t.type, t.is_anime, t.genres, t.network, li.status, li.rating,
    coalesce(ep.episodes, 0)::int AS episodes,
    (coalesce(ep.minutes, 0) + CASE WHEN t.type = 'movie' AND li.status = 'finished'
        THEN coalesce(t.runtime_minutes, 0) ELSE 0 END)::int AS minutes,
    (CASE WHEN t.type = 'book' AND li.status = 'finished' THEN coalesce(t.page_count, 0) ELSE 0 END)::int AS pages
FROM library_items li
JOIN titles t ON t.id = li.title_id
LEFT JOIN LATERAL (
    SELECT count(*) AS episodes, sum(coalesce(se.runtime_minutes, t.runtime_minutes, 0)) AS minutes
    FROM episode_progress p
    LEFT JOIN show_episodes se ON se.title_id = li.title_id AND se.season = p.season AND se.episode = p.episode
    WHERE p.library_item_id = li.id
) ep ON true
WHERE li.user_id = sqlc.arg(user_id);

-- name: StatsMemberSince :one
SELECT created_at FROM users WHERE id = $1;
