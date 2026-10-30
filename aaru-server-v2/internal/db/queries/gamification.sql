-- PostgresGamificationStore*.swift: the points ledger, streak days and badges (GAM-001…005).
-- Library facts read the library and social tables directly, as the Swift store does.

-- MARK: Ledger

-- name: GamificationTotalPoints :many
SELECT total_points FROM user_progress WHERE user_id = $1;

-- name: GamificationLedgerSum :one
SELECT COALESCE(sum(points), 0)::int AS total FROM points_events WHERE user_id = $1;

-- name: GamificationSetTotal :exec
INSERT INTO user_progress (user_id, total_points) VALUES ($1, $2)
ON CONFLICT (user_id) DO UPDATE SET total_points = EXCLUDED.total_points, updated_at = now();

-- name: GamificationAddToTotal :exec
INSERT INTO user_progress (user_id, total_points) VALUES ($1, $2)
ON CONFLICT (user_id) DO UPDATE
SET total_points = user_progress.total_points + EXCLUDED.total_points, updated_at = now();

-- name: GamificationBoardPoints :one
SELECT COALESCE(sum(points), 0)::int AS total FROM points_events
WHERE user_id = sqlc.arg(user_id)
  AND local_date BETWEEN sqlc.arg(from_date)::text::date AND sqlc.arg(until_date)::text::date
  AND kind <> ALL(sqlc.arg(off_board)::text[]);

-- name: GamificationEvents :many
SELECT id, kind, points, title_id, to_char(local_date, 'YYYY-MM-DD')::text AS local_date, created_at,
    (reverses IS NOT NULL)::boolean AS is_revocation
FROM points_events
WHERE user_id = sqlc.arg(user_id)
  AND (sqlc.narg(before)::timestamptz IS NULL OR created_at < sqlc.narg(before)::timestamptz)
ORDER BY created_at DESC, seq DESC
LIMIT sqlc.arg(row_limit);

-- name: GamificationLastEvents :many
SELECT DISTINCT ON (dedupe_root) id, dedupe_root, seq, (reverses IS NOT NULL)::boolean AS revoked
FROM points_events
WHERE user_id = sqlc.arg(user_id) AND dedupe_root = ANY(sqlc.arg(roots)::text[])
ORDER BY dedupe_root, seq DESC;

-- name: GamificationEarnedToday :many
SELECT kind, COALESCE(sum(points), 0)::int AS total FROM points_events
WHERE user_id = sqlc.arg(user_id) AND local_date = sqlc.arg(local_date)::text::date
  AND kind = ANY(sqlc.arg(kinds)::text[])
GROUP BY kind;

-- name: GamificationRevoke :many
-- The negative of each active award, on the award's own local date so an old undo never dents
-- this week's board.
INSERT INTO points_events (id, user_id, kind, points, dedupe_root, seq, dedupe_key, reverses, title_id,
    local_date, time_zone)
SELECT gen_random_uuid(), e.user_id, e.kind, -e.points, e.dedupe_root, e.seq + 1,
    e.dedupe_root || '#' || (e.seq + 1), e.id, e.title_id, e.local_date, e.time_zone
FROM points_events e WHERE e.id = ANY(sqlc.arg(ids)::uuid[])
ON CONFLICT (user_id, dedupe_key) DO NOTHING
RETURNING points;

-- name: GamificationItemTitles :many
SELECT li.id AS item_id, t.id AS title_id, t.type FROM library_items li JOIN titles t ON t.id = li.title_id
WHERE li.id = ANY(sqlc.arg(item_ids)::uuid[]);

-- name: GamificationSeasonComplete :one
-- Every aired regular episode of the season is ticked.
SELECT count(*)::int AS aired, (count(*) FILTER (WHERE ep.id IS NULL))::int AS missing
FROM show_episodes se JOIN titles t ON t.id = se.title_id
LEFT JOIN episode_progress ep ON ep.library_item_id = sqlc.arg(item_id)
    AND ep.season = se.season AND ep.episode = se.episode
WHERE se.title_id = sqlc.arg(title_id) AND se.season = sqlc.arg(season)
  AND (se.airs_at <= now() OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')));

-- MARK: Time zone and streak days

-- name: GamificationStoreZone :exec
INSERT INTO user_progress (user_id, time_zone) VALUES (sqlc.arg(user_id), sqlc.arg(time_zone)::text)
ON CONFLICT (user_id) DO UPDATE SET time_zone = EXCLUDED.time_zone
WHERE user_progress.time_zone IS DISTINCT FROM EXCLUDED.time_zone;

-- name: GamificationStoredZone :many
SELECT time_zone FROM user_progress WHERE user_id = $1;

-- name: GamificationMarkStreakDay :exec
INSERT INTO check_ins (user_id, local_date, time_zone, first_at)
VALUES (sqlc.arg(user_id), sqlc.arg(local_date)::text::date, sqlc.arg(time_zone)::text, sqlc.arg(first_at))
ON CONFLICT (user_id, local_date) DO NOTHING;

-- name: GamificationStreakDays :many
SELECT to_char(local_date, 'YYYY-MM-DD')::text AS local_date, time_zone, first_at FROM check_ins
WHERE user_id = $1 ORDER BY local_date;

-- name: GamificationBackfillStreakDays :exec
-- Only ticks the user made live: imported and restored ticks carry write time, not when they
-- watched (GAM-006a's rule).
INSERT INTO check_ins (user_id, local_date, time_zone, first_at)
SELECT sqlc.arg(user_id)::uuid, (ep.watched_at AT TIME ZONE sqlc.arg(zone)::text)::date,
    sqlc.arg(zone)::text, min(ep.watched_at)
FROM episode_progress ep JOIN library_items li ON li.id = ep.library_item_id
WHERE li.user_id = sqlc.arg(user_id)::uuid AND ep.watched_at_known
GROUP BY 2
ON CONFLICT (user_id, local_date) DO NOTHING;

-- MARK: Badges

-- name: GamificationBadges :many
SELECT id, badge, tier, awarded_at, origin, action_id, seen_at FROM user_badges
WHERE user_id = $1 ORDER BY awarded_at, badge, tier;

-- name: GamificationDeleteBadges :exec
DELETE FROM user_badges WHERE user_id = sqlc.arg(user_id) AND id = ANY(sqlc.arg(ids)::uuid[]);

-- name: GamificationMarkBadgesSeen :exec
UPDATE user_badges SET seen_at = sqlc.arg(seen_at)
WHERE user_id = sqlc.arg(user_id) AND id = ANY(sqlc.arg(ids)::uuid[]) AND seen_at IS NULL;

-- MARK: Worker

-- name: GamificationEvaluatedAt :many
SELECT evaluated_at FROM user_progress WHERE user_id = $1;

-- name: GamificationMarkDirty :exec
-- A batch outranks a live mark: one summary instead of a toast per badge.
INSERT INTO user_progress (user_id, dirty_at, dirty_origin)
VALUES (sqlc.arg(user_id), now(), sqlc.arg(origin)::text)
ON CONFLICT (user_id) DO UPDATE SET dirty_at = now(),
    dirty_origin = CASE
        WHEN user_progress.dirty_origin IN ('batch', 'backfill') AND user_progress.dirty_at IS NOT NULL
        THEN user_progress.dirty_origin ELSE EXCLUDED.dirty_origin END;

-- name: GamificationClaimDirty :many
UPDATE user_progress SET locked_until = now() + make_interval(secs => sqlc.arg(lease_seconds)::float8)
WHERE user_id = (
    SELECT p.user_id FROM user_progress p
    WHERE (p.dirty_at IS NOT NULL OR p.evaluated_at IS NULL) AND (p.locked_until IS NULL OR p.locked_until < now())
    ORDER BY p.dirty_at NULLS LAST
    LIMIT 1 FOR UPDATE SKIP LOCKED
)
RETURNING user_id, dirty_origin, (evaluated_at IS NULL)::boolean AS fresh;

-- name: GamificationFinishEvaluation :exec
INSERT INTO user_progress (user_id, evaluated_at) VALUES (sqlc.arg(user_id), now())
ON CONFLICT (user_id) DO UPDATE SET evaluated_at = now(), locked_until = NULL,
    dirty_at = CASE WHEN user_progress.dirty_at > sqlc.arg(started_at)::timestamptz THEN user_progress.dirty_at END,
    dirty_origin = CASE WHEN user_progress.dirty_at > sqlc.arg(started_at)::timestamptz
        THEN user_progress.dirty_origin END;

-- name: GamificationSeedProgress :many
INSERT INTO user_progress (user_id)
SELECT u.id FROM users u WHERE NOT EXISTS (SELECT 1 FROM user_progress p WHERE p.user_id = u.id)
LIMIT sqlc.arg(row_limit)
ON CONFLICT (user_id) DO NOTHING
RETURNING user_id;

-- MARK: Board

-- name: GamificationLeaderboard :many
-- The viewer and their friends who joined the board, with this week's points. Blocks apply both
-- ways; a viewer who has not joined sees nobody.
WITH people AS (
    SELECT CASE WHEN f.user_low = sqlc.arg(viewer)::uuid THEN f.user_high ELSE f.user_low END AS id
    FROM social_friendships f
    WHERE f.user_low = sqlc.arg(viewer)::uuid OR f.user_high = sqlc.arg(viewer)::uuid
    UNION SELECT sqlc.arg(viewer)::uuid
)
SELECT p.id::uuid AS user_id, COALESCE(sum(e.points), 0)::int AS points
FROM people p
JOIN social_settings s ON s.user_id = p.id AND s.leaderboard_opt_in
LEFT JOIN points_events e ON e.user_id = p.id
    AND e.local_date BETWEEN sqlc.arg(from_date)::text::date AND sqlc.arg(until_date)::text::date
    AND e.kind <> ALL(sqlc.arg(off_board)::text[])
WHERE EXISTS (
    SELECT 1 FROM social_settings v WHERE v.user_id = sqlc.arg(viewer)::uuid AND v.leaderboard_opt_in
)
AND NOT EXISTS (
    SELECT 1 FROM social_blocks b
    WHERE (b.blocker_id = sqlc.arg(viewer)::uuid AND b.blocked_id = p.id)
       OR (b.blocker_id = p.id AND b.blocked_id = sqlc.arg(viewer)::uuid)
)
GROUP BY p.id;

-- name: GamificationSocialSettings :many
-- PostgresFriendViewStore.socialSettings: the two switches gamification reads (no row: defaults).
SELECT show_achievements_to_friends, leaderboard_opt_in FROM social_settings WHERE user_id = $1;

-- name: GamificationFriends :many
-- PostgresSocialStore.friends: the viewer's friends, by handle.
SELECT p.user_id, p.handle, u.display_name, u.avatar_version
FROM social_friendships f
JOIN profiles p ON p.user_id = CASE WHEN f.user_low = sqlc.arg(viewer)::uuid THEN f.user_high ELSE f.user_low END
JOIN users u ON u.id = p.user_id
WHERE f.user_low = sqlc.arg(viewer)::uuid OR f.user_high = sqlc.arg(viewer)::uuid
ORDER BY p.handle;

-- name: GamificationSocialUser :many
-- PostgresSocialStore.socialUser.
SELECT p.user_id, p.handle, u.display_name, u.avatar_version FROM profiles p JOIN users u ON u.id = p.user_id
WHERE p.user_id = $1;

-- name: GamificationTitles :many
-- The titles a page of ledger rows names, for their summaries.
SELECT id, type, title, original_title, year, poster_url, backdrop_url, network, byline, page_count,
    chapter_count, volume_count, is_anime, tmdb, imdb, trakt, tvdb, isbn, open_library, anilist, mal, anidb,
    musicbrainz
FROM titles WHERE id = ANY(sqlc.arg(ids)::uuid[]);

-- MARK: Facts (PostgresGamificationStore+Facts.swift)

-- name: GamificationLibraryFacts :one
SELECT
    (count(*) FILTER (WHERE t.type = 'movie' AND li.status = 'finished'))::int AS films_finished,
    (count(*) FILTER (WHERE t.type = 'movie' AND li.status = 'finished' AND t.year < 1960))::int
        AS films_before1960,
    (count(*) FILTER (WHERE t.type = 'show' AND NOT t.is_anime AND li.status = 'finished'))::int
        AS shows_finished,
    (count(*) FILTER (WHERE t.type = 'show' AND t.is_anime AND li.status = 'finished'))::int AS anime_finished,
    (count(*) FILTER (WHERE t.type = 'book' AND li.status = 'finished'))::int AS books_finished,
    COALESCE(sum(CASE WHEN t.type <> 'book' THEN 0
        WHEN li.status = 'finished' THEN COALESCE(t.page_count, li.book_page, 0)
        ELSE COALESCE(li.book_page, 0) END), 0)::int AS pages_read,
    (count(*) FILTER (WHERE t.type = 'book' AND li.status = 'finished' AND t.page_count >= 800))::int
        AS long_books_finished,
    (count(*) FILTER (WHERE t.type = 'album' AND li.status = 'finished'))::int AS albums_finished,
    count(li.rating)::int AS ratings,
    (count(*) FILTER (WHERE li.rating = 10))::int AS perfect_tens,
    (avg(li.rating) IS NOT NULL)::boolean AS has_rating_mean,
    COALESCE(avg(li.rating), 0)::float8 AS rating_mean,
    (count(*) FILTER (WHERE btrim(COALESCE(li.notes, '')) <> ''))::int AS notes,
    (count(*) FILTER (WHERE li.is_owned))::int AS owned,
    (count(DISTINCT t.year / 10) FILTER (WHERE li.status = 'finished' AND t.year IS NOT NULL))::int AS decades
FROM library_items li JOIN titles t ON t.id = li.title_id
WHERE li.user_id = $1;

-- name: GamificationSpreadFacts :one
-- Genres and networks reached: the Discovery badges.
SELECT
    (SELECT count(DISTINCT g)::int FROM library_items li JOIN titles t ON t.id = li.title_id,
        unnest(t.genres) AS g
     WHERE li.user_id = sqlc.arg(user_id)::uuid AND li.status = 'finished')::int AS genres,
    (SELECT count(DISTINCT t.network)::int FROM library_items li JOIN titles t ON t.id = li.title_id
     WHERE li.user_id = sqlc.arg(user_id)::uuid AND t.type = 'show' AND t.network IS NOT NULL
       AND EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id))::int AS networks;

-- name: GamificationShowFacts :one
WITH aired AS (
    SELECT li.id AS item, t.status, se.season, count(*) AS aired, count(ep.id) AS watched
    FROM library_items li
    JOIN titles t ON t.id = li.title_id AND t.type = 'show'
    JOIN show_episodes se ON se.title_id = li.title_id AND se.season > 0
    LEFT JOIN episode_progress ep ON ep.library_item_id = li.id
        AND ep.season = se.season AND ep.episode = se.episode
    WHERE li.user_id = sqlc.arg(user_id)::uuid
      AND (se.airs_at <= now() OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')))
    GROUP BY li.id, t.status, se.season
), shows AS (
    SELECT item, status, bool_and(watched = aired) AS done, sum(aired) AS aired FROM aired GROUP BY item, status
)
SELECT
    (SELECT count(*)::int FROM episode_progress ep JOIN library_items li ON li.id = ep.library_item_id
     WHERE li.user_id = sqlc.arg(user_id)::uuid)::int AS episodes,
    (SELECT count(*)::int FROM episode_progress ep JOIN library_items li ON li.id = ep.library_item_id
     JOIN titles t ON t.id = li.title_id WHERE li.user_id = sqlc.arg(user_id)::uuid AND t.is_anime)::int
        AS anime_episodes,
    (SELECT count(*)::int FROM aired WHERE watched = aired)::int AS seasons,
    (SELECT count(*)::int FROM shows WHERE done AND status IN ('ended', 'canceled'))::int AS ended_complete,
    (SELECT count(*)::int FROM shows WHERE done AND aired >= 100)::int AS long_complete;

-- name: GamificationOtherFacts :one
SELECT
    (SELECT count(*)::int FROM lists WHERE user_id = sqlc.arg(user_id)::uuid)::int AS lists,
    (SELECT count(*)::int FROM saved_queries WHERE user_id = sqlc.arg(user_id)::uuid)::int AS shelves,
    (SELECT count(*)::int FROM listens WHERE user_id = sqlc.arg(user_id)::uuid)::int AS listens,
    (SELECT count(DISTINCT COALESCE(artist_mbid, lower(artist)))::int FROM listens
     WHERE user_id = sqlc.arg(user_id)::uuid)::int AS artists,
    (SELECT count(*)::int FROM social_friendships
     WHERE user_low = sqlc.arg(user_id)::uuid OR user_high = sqlc.arg(user_id)::uuid)::int AS friends,
    (SELECT count(*)::int FROM social_invites
     WHERE inviter_id = sqlc.arg(user_id)::uuid AND redeemed_by IS NOT NULL)::int AS invites_redeemed,
    (SELECT count(*)::int FROM social_recommendations WHERE from_user_id = sqlc.arg(user_id)::uuid)::int
        AS recommendations_sent,
    (SELECT count(*)::int FROM social_recommendations
     WHERE from_user_id = sqlc.arg(user_id)::uuid AND added_at IS NOT NULL)::int AS recommendations_added,
    (SELECT count(*)::int FROM social_reactions WHERE user_id = sqlc.arg(user_id)::uuid)::int AS reactions;

-- name: GamificationImportSources :many
SELECT DISTINCT source FROM import_jobs WHERE user_id = $1 AND state IN ('succeeded', 'partial');

-- name: GamificationLedgerFacts :one
-- Active awards only: an award whose revocation exists no longer counts.
WITH active AS (
    SELECT e.* FROM points_events e
    WHERE e.user_id = sqlc.arg(user_id)::uuid AND e.reverses IS NULL
      AND NOT EXISTS (SELECT 1 FROM points_events r WHERE r.reverses = e.id)
), episodes AS (
    SELECT a.*, split_part(a.dedupe_root, ':', 3)::int AS season,
        split_part(a.dedupe_root, ':', 4)::int AS episode
    FROM active a WHERE a.kind = 'episode'
), aired AS (
    SELECT e.created_at, se.airs_at, se.airs_at_exact, se.title_id, se.season, se.episode
    FROM episodes e JOIN show_episodes se
        ON se.title_id = e.title_id AND se.season = e.season AND se.episode = e.episode
    WHERE se.airs_at IS NOT NULL AND e.created_at >= se.airs_at
      AND e.created_at < se.airs_at + interval '24 hours'
)
SELECT
    (SELECT count(*)::int FROM (SELECT local_date FROM active WHERE kind = 'movie_finished'
        GROUP BY local_date HAVING count(*) >= 2) d)::int AS double_feature_days,
    (SELECT count(*)::int FROM (SELECT local_date FROM active WHERE kind = 'episode'
        GROUP BY local_date HAVING count(*) >= 10) d)::int AS marathon_days,
    (SELECT count(*)::int FROM active WHERE kind = ANY(sqlc.arg(streak_kinds)::text[])
        AND extract(hour FROM created_at AT TIME ZONE time_zone) < 5)::int AS night_owl,
    (SELECT count(*)::int FROM active WHERE kind = 'room_attended')::int AS parties,
    (SELECT count(*)::int FROM aired WHERE airs_at_exact)::int AS day_one,
    (SELECT count(*)::int FROM aired a WHERE a.season > 0 AND a.episode = (
        SELECT max(x.episode) FROM show_episodes x WHERE x.title_id = a.title_id AND x.season = a.season
    ))::int AS finales,
    (SELECT count(*)::int FROM active sb
     CROSS JOIN LATERAL (
        SELECT count(*) AS size FROM show_episodes x
        WHERE x.title_id = sb.title_id AND x.season = split_part(sb.dedupe_root, ':', 3)::int
     ) s
     WHERE sb.kind = 'season_bonus' AND s.size >= 6 AND (
        SELECT count(*) FROM episodes e WHERE e.title_id = sb.title_id AND e.local_date = sb.local_date
          AND e.season = split_part(sb.dedupe_root, ':', 3)::int
     ) >= s.size)::int AS binged;

-- name: GamificationBookDays :many
-- The days with book progress: Chapter a Day.
SELECT DISTINCT to_char(local_date, 'YYYY-MM-DD')::text AS local_date FROM points_events e
WHERE e.user_id = $1 AND e.kind = 'book_progress' AND e.reverses IS NULL
  AND NOT EXISTS (SELECT 1 FROM points_events r WHERE r.reverses = e.id);
