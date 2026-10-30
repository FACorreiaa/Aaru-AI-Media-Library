-- PostgresLibraryStore+Lists.swift (list ops, journaled like every library write) and
-- PostgresStores.swift's PostgresListStore and PostgresShelfStore.

-- MARK: List ops (run inside the library transaction)

-- name: ListInsert :exec
INSERT INTO lists (id, user_id, name, created_at, updated_at)
VALUES (@id, @user_id, @name, @created_at, now());

-- name: ListLock :one
SELECT name, created_at FROM lists WHERE id = @id AND user_id = @user_id FOR UPDATE;

-- name: ListMemberIDs :many
SELECT title_id FROM list_items WHERE list_id = @list_id ORDER BY position;

-- name: ListDelete :exec
DELETE FROM lists WHERE id = @id;

-- name: ListRename :exec
UPDATE lists SET name = @name, updated_at = now() WHERE id = @id;

-- name: ListTouch :exec
UPDATE lists SET updated_at = now() WHERE id = @id;

-- name: ListClearMembers :exec
DELETE FROM list_items WHERE list_id = @list_id;

-- name: ListWriteMembers :exec
-- One statement for the whole list; the array index is the position, from 0.
INSERT INTO list_items (id, list_id, title_id, position)
SELECT (@ids::uuid[])[i], @list_id, (@title_ids::uuid[])[i], (i - 1)::int
FROM generate_subscripts(@title_ids::uuid[], 1) AS i;

-- MARK: List reads

-- name: ListsOfUser :many
SELECT id, user_id, name, created_at, updated_at FROM lists
WHERE user_id = @user_id AND (sqlc.narg(id)::uuid IS NULL OR id = sqlc.narg(id)::uuid)
ORDER BY created_at;

-- name: ListMembersOf :many
SELECT list_id, title_id FROM list_items WHERE list_id = ANY(@list_ids::uuid[]) ORDER BY position;

-- MARK: Shelves (saved queries, never membership)

-- name: ShelvesOfUser :many
SELECT id, name, filter, is_pinned, created_at FROM saved_queries
WHERE user_id = @user_id ORDER BY is_pinned DESC, created_at;

-- name: ShelfByID :one
SELECT id, name, filter, is_pinned, created_at FROM saved_queries
WHERE id = @id AND user_id = @user_id;

-- name: ShelfSave :exec
INSERT INTO saved_queries (id, user_id, name, filter, is_pinned, created_at)
VALUES (@id, @user_id, @name, @filter, @is_pinned, @created_at)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, filter = EXCLUDED.filter,
    is_pinned = EXCLUDED.is_pinned, updated_at = now()
WHERE saved_queries.user_id = @user_id;

-- name: ShelfDelete :many
DELETE FROM saved_queries WHERE id = @id AND user_id = @user_id RETURNING id;
