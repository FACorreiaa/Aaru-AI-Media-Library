-- GET /v1/me/export (AccountExport.swift, ExportHandlers.swift): the reads that have no store
-- method of their own. Friends, blocks, the avatar and listens go through the social and music
-- stores.

-- name: ExportLists :many
-- PostgresListStore.lists(userID:)
SELECT id, name, created_at FROM lists WHERE user_id = $1 ORDER BY created_at;

-- name: ExportListItems :many
SELECT list_id, title_id FROM list_items WHERE list_id = ANY(sqlc.arg(list_ids)::uuid[]) ORDER BY position;

-- name: ExportShelves :many
-- PostgresShelfStore.shelves(userID:)
SELECT id, name, filter, is_pinned FROM saved_queries
WHERE user_id = $1 ORDER BY is_pinned DESC, created_at;

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

-- name: ExportFavorites :many
-- PostgresFavoriteStore.favorites(of:)
SELECT kind, title_id FROM favorites WHERE user_id = $1 ORDER BY kind, position;
