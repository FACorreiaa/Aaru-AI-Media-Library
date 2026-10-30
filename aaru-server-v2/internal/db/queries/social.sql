-- Social: handles, friends, blocks, reports, avatars, invites (PostgresSocialStore*.swift),
-- settings, friend profiles and activity (PostgresFriendViewStore.swift), reactions and
-- recommendations (PostgresInteractionStore.swift), favorites (PostgresFavoriteStore.swift).

-- name: SocialUserByID :one
SELECT p.user_id, p.handle, u.display_name, u.avatar_version
FROM profiles p JOIN users u ON u.id = p.user_id
WHERE p.user_id = $1;

-- name: SocialUserByHandle :one
SELECT p.user_id, p.handle, u.display_name, u.avatar_version
FROM profiles p JOIN users u ON u.id = p.user_id
WHERE p.handle = $1;

-- name: SocialSaveHandle :exec
INSERT INTO profiles (user_id, handle) VALUES ($1, $2)
ON CONFLICT (user_id) DO UPDATE SET handle = EXCLUDED.handle, updated_at = now();

-- name: SocialSaveNames :exec
UPDATE users SET first_name = sqlc.narg(first_name), last_name = sqlc.narg(last_name),
    display_name = sqlc.narg(display_name), updated_at = now()
WHERE id = sqlc.arg(id);

-- name: SocialIsBlocked :one
SELECT EXISTS (
    SELECT 1 FROM social_blocks
    WHERE (blocker_id = sqlc.arg(first)::uuid AND blocked_id = sqlc.arg(second)::uuid)
       OR (blocker_id = sqlc.arg(second)::uuid AND blocked_id = sqlc.arg(first)::uuid)
) AS found;

-- name: SocialAreFriends :one
SELECT EXISTS (
    SELECT 1 FROM social_friendships
    WHERE user_low = LEAST(sqlc.arg(first)::uuid, sqlc.arg(second)::uuid)
      AND user_high = GREATEST(sqlc.arg(first)::uuid, sqlc.arg(second)::uuid)
) AS found;

-- name: SocialFriendsSince :one
SELECT created_at FROM social_friendships
WHERE user_low = LEAST(sqlc.arg(first)::uuid, sqlc.arg(second)::uuid)
  AND user_high = GREATEST(sqlc.arg(first)::uuid, sqlc.arg(second)::uuid);

-- name: SocialPendingRequest :one
SELECT id FROM social_friend_requests WHERE from_user_id = $1 AND to_user_id = $2;

-- name: SocialCreateRequest :exec
INSERT INTO social_friend_requests (id, from_user_id, to_user_id, created_at)
VALUES ($1, $2, $3, $4)
ON CONFLICT (from_user_id, to_user_id) DO NOTHING;

-- name: SocialIncomingRequests :many
SELECT r.id, r.created_at,
       r.from_user_id, fp.handle AS from_handle, fu.display_name AS from_display_name,
       fu.avatar_version AS from_avatar_version,
       r.to_user_id, tp.handle AS to_handle, tu.display_name AS to_display_name,
       tu.avatar_version AS to_avatar_version
FROM social_friend_requests r
JOIN profiles fp ON fp.user_id = r.from_user_id JOIN users fu ON fu.id = r.from_user_id
JOIN profiles tp ON tp.user_id = r.to_user_id JOIN users tu ON tu.id = r.to_user_id
WHERE r.to_user_id = $1
ORDER BY r.created_at DESC;

-- name: SocialOutgoingRequests :many
SELECT r.id, r.created_at,
       r.from_user_id, fp.handle AS from_handle, fu.display_name AS from_display_name,
       fu.avatar_version AS from_avatar_version,
       r.to_user_id, tp.handle AS to_handle, tu.display_name AS to_display_name,
       tu.avatar_version AS to_avatar_version
FROM social_friend_requests r
JOIN profiles fp ON fp.user_id = r.from_user_id JOIN users fu ON fu.id = r.from_user_id
JOIN profiles tp ON tp.user_id = r.to_user_id JOIN users tu ON tu.id = r.to_user_id
WHERE r.from_user_id = $1
ORDER BY r.created_at DESC;

-- name: SocialTakeRequest :one
DELETE FROM social_friend_requests
WHERE id = $1 AND to_user_id = $2
RETURNING from_user_id;

-- name: SocialDeleteRequestFrom :exec
DELETE FROM social_friend_requests WHERE from_user_id = $1 AND to_user_id = $2;

-- name: SocialDeleteRequestsBetween :exec
DELETE FROM social_friend_requests
WHERE (from_user_id = sqlc.arg(first)::uuid AND to_user_id = sqlc.arg(second)::uuid)
   OR (from_user_id = sqlc.arg(second)::uuid AND to_user_id = sqlc.arg(first)::uuid);

-- name: SocialWithdrawRequest :execrows
DELETE FROM social_friend_requests
WHERE id = sqlc.arg(id) AND (from_user_id = sqlc.arg(party)::uuid OR to_user_id = sqlc.arg(party)::uuid);

-- name: SocialInsertFriendship :exec
INSERT INTO social_friendships (user_low, user_high, created_at)
VALUES (LEAST(sqlc.arg(first)::uuid, sqlc.arg(second)::uuid),
        GREATEST(sqlc.arg(first)::uuid, sqlc.arg(second)::uuid), sqlc.arg(created_at))
ON CONFLICT DO NOTHING;

-- name: SocialDeleteFriendship :execrows
DELETE FROM social_friendships
WHERE user_low = LEAST(sqlc.arg(first)::uuid, sqlc.arg(second)::uuid)
  AND user_high = GREATEST(sqlc.arg(first)::uuid, sqlc.arg(second)::uuid);

-- name: SocialDropGroupInvites :exec
-- GRP-013: group invites are friends-only, so they end with the friendship. Only the pair's
-- own invites go; another member's invite to either of them stays.
DELETE FROM group_invites
WHERE (inviter_id = sqlc.arg(first)::uuid AND invitee_id = sqlc.arg(second)::uuid)
   OR (inviter_id = sqlc.arg(second)::uuid AND invitee_id = sqlc.arg(first)::uuid);

-- name: SocialFriends :many
SELECT p.user_id, p.handle, u.display_name, u.avatar_version
FROM social_friendships f
JOIN profiles p ON p.user_id = CASE WHEN f.user_low = sqlc.arg(user_id)::uuid THEN f.user_high ELSE f.user_low END
JOIN users u ON u.id = p.user_id
WHERE f.user_low = sqlc.arg(user_id)::uuid OR f.user_high = sqlc.arg(user_id)::uuid
ORDER BY p.handle;

-- name: SocialInsertBlock :exec
INSERT INTO social_blocks (blocker_id, blocked_id, created_at) VALUES ($1, $2, $3)
ON CONFLICT DO NOTHING;

-- name: SocialUnblock :execrows
DELETE FROM social_blocks WHERE blocker_id = $1 AND blocked_id = $2;

-- name: SocialBlocked :many
SELECT p.user_id, p.handle, u.display_name, u.avatar_version
FROM social_blocks b JOIN profiles p ON p.user_id = b.blocked_id JOIN users u ON u.id = p.user_id
WHERE b.blocker_id = $1
ORDER BY p.handle;

-- name: SocialBlockers :many
SELECT blocker_id FROM social_blocks WHERE blocked_id = $1;

-- name: SocialReport :exec
INSERT INTO social_reports (id, reporter_id, target_user_id, reason, note, created_at)
VALUES ($1, $2, $3, $4, $5, $6);

-- name: SocialSaveAvatar :exec
INSERT INTO avatars (user_id, image) VALUES ($1, $2)
ON CONFLICT (user_id) DO UPDATE SET image = EXCLUDED.image, updated_at = now();

-- name: SocialBumpAvatarVersion :exec
-- Milliseconds, not a counter: a removed avatar's version is never handed out again.
UPDATE users SET avatar_version = GREATEST(
    (extract(epoch FROM clock_timestamp()) * 1000)::bigint, coalesce(avatar_version, 0) + 1
), updated_at = now()
WHERE id = $1;

-- name: SocialDeleteAvatar :exec
DELETE FROM avatars WHERE user_id = $1;

-- name: SocialClearAvatarVersion :exec
UPDATE users SET avatar_version = NULL, updated_at = now() WHERE id = $1;

-- name: SocialAvatar :one
SELECT image FROM avatars WHERE user_id = $1;

-- name: SocialCreateInvite :exec
INSERT INTO social_invites (id, code, inviter_id, title_id, created_at, expires_at)
VALUES ($1, $2, $3, $4, $5, $6);

-- name: SocialInvite :one
SELECT id, code, inviter_id, title_id, created_at, expires_at, redeemed_by, redeemed_at, revoked_at
FROM social_invites WHERE code = $1;

-- name: SocialOpenInvites :many
SELECT id, code, inviter_id, title_id, created_at, expires_at, redeemed_by, redeemed_at, revoked_at
FROM social_invites
WHERE inviter_id = sqlc.arg(inviter_id)
  AND redeemed_at IS NULL AND revoked_at IS NULL AND expires_at > sqlc.arg(now)
ORDER BY created_at DESC;

-- name: SocialRevokeInvite :execrows
UPDATE social_invites SET revoked_at = sqlc.arg(now)
WHERE code = sqlc.arg(code) AND inviter_id = sqlc.arg(inviter_id)
  AND redeemed_at IS NULL AND revoked_at IS NULL AND expires_at > sqlc.arg(now);

-- name: SocialRedeemInvite :one
-- The conditional update is the lock: of two people opening one link at once, one wins.
UPDATE social_invites SET redeemed_by = sqlc.arg(redeemer)::uuid, redeemed_at = sqlc.arg(now)
WHERE code = sqlc.arg(code) AND inviter_id <> sqlc.arg(redeemer)::uuid
  AND redeemed_at IS NULL AND revoked_at IS NULL AND expires_at > sqlc.arg(now)
RETURNING inviter_id;

-- name: SocialSettings :one
SELECT share_library_with_friends, show_achievements_to_friends, leaderboard_opt_in,
    share_email_with_friends
FROM social_settings WHERE user_id = $1;

-- name: SocialSaveSettings :exec
INSERT INTO social_settings (user_id, share_library_with_friends, show_achievements_to_friends,
    leaderboard_opt_in, share_email_with_friends)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (user_id) DO UPDATE
SET share_library_with_friends = EXCLUDED.share_library_with_friends,
    show_achievements_to_friends = EXCLUDED.show_achievements_to_friends,
    leaderboard_opt_in = EXCLUDED.leaderboard_opt_in,
    share_email_with_friends = EXCLUDED.share_email_with_friends, updated_at = now();

-- name: SocialKindCounts :many
SELECT (CASE WHEN t.is_anime THEN 'anime' ELSE t.type END)::text AS kind, count(*)::int AS count
FROM library_items li JOIN titles t ON t.id = li.title_id
WHERE li.user_id = $1 AND li.status <> 'dropped'
GROUP BY 1;

-- name: SocialBothWant :many
SELECT a.title_id FROM library_items a
JOIN library_items b ON b.title_id = a.title_id AND b.user_id = sqlc.arg(viewer)::uuid
    AND b.status = 'wishlist'
WHERE a.user_id = sqlc.arg(owner)::uuid AND a.status = 'wishlist'
ORDER BY a.updated_at DESC LIMIT sqlc.arg(max_rows);

-- name: SocialTheyLoved :many
SELECT a.title_id FROM library_items a
WHERE a.user_id = sqlc.arg(owner)::uuid AND a.rating >= 8
  AND NOT EXISTS (
      SELECT 1 FROM library_items b WHERE b.user_id = sqlc.arg(viewer)::uuid AND b.title_id = a.title_id
  )
ORDER BY a.rating DESC, a.finished_at DESC NULLS LAST LIMIT sqlc.arg(max_rows);

-- name: SocialBothFinished :one
SELECT count(*)::int AS count FROM library_items a
JOIN library_items b ON b.title_id = a.title_id AND b.user_id = sqlc.arg(viewer)::uuid
    AND b.status = 'finished'
WHERE a.user_id = sqlc.arg(owner)::uuid AND a.status = 'finished';

-- name: SocialReactions :many
SELECT r.owner_id, r.title_id, r.day::text AS day, r.emoji, count(*)::int AS count,
    bool_or(r.user_id = sqlc.arg(viewer)::uuid)::bool AS mine
FROM social_reactions r
-- Each column against its own list; the service keeps only the exact (owner, title, day) keys
-- (sqlc cannot read a multi-array unnest).
WHERE r.owner_id = ANY(sqlc.arg(owners)::uuid[]) AND r.title_id = ANY(sqlc.arg(titles)::uuid[])
  AND r.day::text = ANY(sqlc.arg(days)::text[])
GROUP BY r.owner_id, r.title_id, r.day, r.emoji;

-- name: SocialClearReaction :exec
DELETE FROM social_reactions
WHERE user_id = sqlc.arg(user_id) AND owner_id = sqlc.arg(owner_id)
  AND title_id = sqlc.arg(title_id) AND day = sqlc.arg(day)::text::date;

-- name: SocialSetReaction :exec
INSERT INTO social_reactions (user_id, owner_id, title_id, day, emoji, created_at)
VALUES (sqlc.arg(user_id), sqlc.arg(owner_id), sqlc.arg(title_id), sqlc.arg(day)::text::date,
        sqlc.arg(emoji), sqlc.arg(created_at))
ON CONFLICT (user_id, owner_id, title_id, day)
DO UPDATE SET emoji = EXCLUDED.emoji, created_at = EXCLUDED.created_at;

-- name: SocialHasTitle :one
SELECT EXISTS (
    SELECT 1 FROM library_items WHERE user_id = $1 AND title_id = $2
) AS found;

-- name: SocialRecommend :exec
INSERT INTO social_recommendations (id, from_user_id, to_user_id, title_id, note, created_at)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (from_user_id, to_user_id, title_id) WHERE added_at IS NULL AND dismissed_at IS NULL
DO NOTHING;

-- name: SocialInbox :many
SELECT r.id, r.from_user_id, r.to_user_id, r.title_id, r.note, r.created_at
FROM social_recommendations r
JOIN social_friendships f
    ON f.user_low = LEAST(r.from_user_id, r.to_user_id) AND f.user_high = GREATEST(r.from_user_id, r.to_user_id)
WHERE r.to_user_id = $1 AND r.added_at IS NULL AND r.dismissed_at IS NULL
ORDER BY r.created_at DESC
LIMIT $2;

-- name: SocialMarkRecommendationAdded :one
UPDATE social_recommendations SET added_at = sqlc.arg(now)
WHERE id = sqlc.arg(id) AND to_user_id = sqlc.arg(user_id) AND added_at IS NULL AND dismissed_at IS NULL
RETURNING id, from_user_id, to_user_id, title_id, note, created_at;

-- name: SocialMarkRecommendationDismissed :one
UPDATE social_recommendations SET dismissed_at = sqlc.arg(now)
WHERE id = sqlc.arg(id) AND to_user_id = sqlc.arg(user_id) AND added_at IS NULL AND dismissed_at IS NULL
RETURNING id, from_user_id, to_user_id, title_id, note, created_at;

-- name: FavoritesOf :many
SELECT kind, title_id FROM favorites WHERE user_id = $1 ORDER BY kind, position;

-- name: FavoritesClearKind :exec
DELETE FROM favorites WHERE user_id = $1 AND kind = $2;

-- name: FavoritesInsertKind :exec
-- `ordinality` is the position, from 0.
INSERT INTO favorites (user_id, kind, position, title_id)
SELECT sqlc.arg(user_id)::uuid, sqlc.arg(kind)::text, (f.position - 1)::int, f.title_id
FROM unnest(sqlc.arg(title_ids)::uuid[]) WITH ORDINALITY AS f(title_id, position);
