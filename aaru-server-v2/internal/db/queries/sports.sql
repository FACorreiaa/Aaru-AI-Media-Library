-- PostgresSportsStore.swift: follows and the "Where to watch" country (SPT-001).

-- name: SportFollows :many
SELECT kind, provider_id, name, sport, badge_url, country, league_id, team_id, team_name, created_at
FROM sport_follows WHERE user_id = $1
ORDER BY created_at, kind, provider_id;

-- One writer per user at a time, so two follows racing at the limit cannot both pass.
-- name: LockUserForSportFollow :exec
SELECT 1 FROM users WHERE id = $1 FOR UPDATE;

-- name: SportFollowCounts :one
SELECT count(*)::int AS count,
    (count(*) FILTER (WHERE kind = sqlc.arg(kind) AND provider_id = sqlc.arg(provider_id)))::int AS existing
FROM sport_follows WHERE user_id = sqlc.arg(user_id);

-- name: UpsertSportFollow :exec
INSERT INTO sport_follows (user_id, kind, provider_id, name, sport, badge_url, country, league_id,
    team_id, team_name, created_at)
VALUES (sqlc.arg(user_id), sqlc.arg(kind), sqlc.arg(provider_id), sqlc.arg(name), sqlc.arg(sport),
    sqlc.narg(badge_url), sqlc.narg(country), sqlc.narg(league_id), sqlc.narg(team_id), sqlc.narg(team_name),
    sqlc.arg(created_at))
ON CONFLICT (user_id, kind, provider_id) DO UPDATE SET name = EXCLUDED.name, sport = EXCLUDED.sport,
    badge_url = EXCLUDED.badge_url, country = EXCLUDED.country, league_id = EXCLUDED.league_id,
    team_id = EXCLUDED.team_id, team_name = EXCLUDED.team_name;

-- name: DeleteSportFollow :exec
DELETE FROM sport_follows WHERE user_id = $1 AND kind = $2 AND provider_id = $3;

-- name: SportWatchCountry :one
SELECT watch_country_code FROM sport_settings WHERE user_id = $1;

-- name: SaveSportWatchCountry :exec
INSERT INTO sport_settings (user_id, watch_country_code, updated_at)
VALUES (sqlc.arg(user_id), sqlc.narg(watch_country_code), sqlc.arg(updated_at))
ON CONFLICT (user_id) DO UPDATE SET watch_country_code = EXCLUDED.watch_country_code,
    updated_at = EXCLUDED.updated_at;
