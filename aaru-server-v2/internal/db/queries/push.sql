-- PostgresPushStore.swift: APNs devices, notification switches, airing claims, web push.

-- name: RegisterPushDevice :exec
INSERT INTO apns_devices (token, user_id, environment, topic, updated_at)
VALUES ($1, $2, $3, $4, now())
ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, environment = EXCLUDED.environment,
    topic = EXCLUDED.topic, updated_at = now();

-- name: UnregisterPushDevice :exec
DELETE FROM apns_devices WHERE token = $1 AND user_id = $2;

-- name: ForgetPushDevice :exec
DELETE FROM apns_devices WHERE token = $1;

-- name: PushDevices :many
SELECT token, environment, topic FROM apns_devices WHERE user_id = $1;

-- name: NotificationSettings :one
SELECT airing, group_mentions, group_invites FROM notification_settings WHERE user_id = $1;

-- name: SaveNotificationSettings :exec
INSERT INTO notification_settings (user_id, airing, airing_since, group_mentions, group_invites)
VALUES (sqlc.arg(user_id), sqlc.arg(airing), sqlc.narg(airing_since),
    sqlc.arg(group_mentions), sqlc.arg(group_invites))
ON CONFLICT (user_id) DO UPDATE SET airing = EXCLUDED.airing,
    airing_since = CASE WHEN EXCLUDED.airing AND NOT notification_settings.airing
        THEN EXCLUDED.airing_since ELSE notification_settings.airing_since END,
    group_mentions = EXCLUDED.group_mentions, group_invites = EXCLUDED.group_invites;

-- name: MentionRecipients :many
SELECT gm.user_id FROM group_members gm
JOIN notification_settings ns ON ns.user_id = gm.user_id AND ns.group_mentions
WHERE gm.group_id = sqlc.arg(group_id) AND NOT gm.muted
  AND gm.user_id = ANY(sqlc.arg(users)::uuid[]);

-- name: DueAirings :many
SELECT li.user_id, li.title_id, li.id AS library_item_id, t.title, se.season, se.episode, se.name
FROM show_episodes se
JOIN titles t ON t.id = se.title_id
JOIN library_items li ON li.title_id = se.title_id AND li.status = 'in_progress'
JOIN notification_settings ns ON ns.user_id = li.user_id AND ns.airing
WHERE se.season > 0
  AND se.airs_at > sqlc.arg(since) AND se.airs_at <= sqlc.arg(now)
  AND se.airs_at > ns.airing_since
  AND (EXISTS (SELECT 1 FROM apns_devices d WHERE d.user_id = li.user_id)
       OR EXISTS (SELECT 1 FROM web_push_subscriptions w WHERE w.user_id = li.user_id))
  AND NOT EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
                  AND ep.season = se.season AND ep.episode = se.episode)
  AND NOT EXISTS (SELECT 1 FROM notifications_sent sent WHERE sent.user_id = li.user_id
                  AND sent.title_id = se.title_id AND sent.season = se.season AND sent.episode = se.episode)
ORDER BY se.airs_at
LIMIT 500;

-- name: ClaimAiring :many
INSERT INTO notifications_sent (user_id, title_id, season, episode)
VALUES ($1, $2, $3, $4)
ON CONFLICT DO NOTHING RETURNING season;

-- name: SaveWebPushSubscription :exec
INSERT INTO web_push_subscriptions (endpoint, user_id, p256dh, auth, vapid_key_id, updated_at)
VALUES ($1, $2, $3, $4, $5, now())
ON CONFLICT (endpoint) DO UPDATE SET user_id = EXCLUDED.user_id, p256dh = EXCLUDED.p256dh,
    auth = EXCLUDED.auth, vapid_key_id = EXCLUDED.vapid_key_id, updated_at = now();

-- name: DeleteWebPushSubscription :exec
DELETE FROM web_push_subscriptions WHERE endpoint = $1 AND user_id = $2;

-- name: ForgetWebPushSubscription :exec
DELETE FROM web_push_subscriptions WHERE endpoint = $1;

-- name: WebPushSubscriptions :many
SELECT endpoint, p256dh, auth, vapid_key_id FROM web_push_subscriptions
WHERE user_id = $1 ORDER BY updated_at DESC;
