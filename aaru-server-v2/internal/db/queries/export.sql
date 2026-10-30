-- GET /v1/me/export (AccountExport.swift, ExportHandlers.swift). Each read mirrors the Swift
-- store the export called (lists, shelves, social, groups, listens, favorites); those areas are
-- ported on their own branches, so fold these into their queries after merge.

-- name: ExportLists :many
-- PostgresListStore.lists(userID:)
SELECT id, name, created_at FROM lists WHERE user_id = $1 ORDER BY created_at;

-- name: ExportListItems :many
SELECT list_id, title_id FROM list_items WHERE list_id = ANY(sqlc.arg(list_ids)::uuid[]) ORDER BY position;

-- name: ExportShelves :many
-- PostgresShelfStore.shelves(userID:)
SELECT id, name, filter, is_pinned FROM saved_queries
WHERE user_id = $1 ORDER BY is_pinned DESC, created_at;

-- name: ExportFriends :many
-- PostgresSocialStore.friends(_:)
SELECT p.user_id, p.handle, u.display_name, u.avatar_version
FROM social_friendships f
JOIN profiles p ON p.user_id = CASE WHEN f.user_low = sqlc.arg(user_id)::uuid THEN f.user_high ELSE f.user_low END
JOIN users u ON u.id = p.user_id
WHERE f.user_low = sqlc.arg(user_id)::uuid OR f.user_high = sqlc.arg(user_id)::uuid
ORDER BY p.handle;

-- name: ExportBlocked :many
-- PostgresSocialStore.blocked(by:)
SELECT p.user_id, p.handle, u.display_name, u.avatar_version
FROM social_blocks b JOIN profiles p ON p.user_id = b.blocked_id JOIN users u ON u.id = p.user_id
WHERE b.blocker_id = $1
ORDER BY p.handle;

-- name: ExportAvatar :many
-- PostgresSocialStore.avatar(_:)
SELECT image FROM avatars WHERE user_id = $1;

-- name: ExportGroups :many
-- PostgresGroupStore.groups(for:), the name and role only.
SELECT g.name, gm.role
FROM group_members gm JOIN groups g ON g.id = gm.group_id
WHERE gm.user_id = $1
ORDER BY gm.joined_at, g.id;

-- name: ExportGroupMessages :many
-- PostgresGroupStore.exportMessages(_:)
SELECT g.name AS group_name, c.name AS channel_name, m.body, m.created_at
FROM group_messages m JOIN group_channels c ON c.id = m.channel_id JOIN groups g ON g.id = c.group_id
WHERE m.author_id = $1 AND m.deleted_at IS NULL
ORDER BY m.created_at;

-- name: ExportListens :many
-- PostgresListenStore.listens(userID:before:nil, limit:.max)
SELECT l.id, l.listened_at, l.artist, l.track, l.album, l.duration_ms, l.release_group_mbid,
       t.id AS album_title_id, l.origin_url, l.client, l.music_service
FROM listens l
LEFT JOIN titles t ON t.musicbrainz = l.release_group_mbid
WHERE l.user_id = $1
ORDER BY l.listened_at DESC, l.id DESC;

-- name: ExportFavorites :many
-- PostgresFavoriteStore.favorites(of:)
SELECT kind, title_id FROM favorites WHERE user_id = $1 ORDER BY kind, position;
