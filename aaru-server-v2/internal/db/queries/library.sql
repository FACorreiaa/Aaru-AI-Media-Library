-- PostgresLibraryStore*.swift: library items, episode ticks, the action journal and undo.
-- The entry reads (an item with its title and derived show progress) are dynamic and live in
-- internal/library/entries.go.

-- MARK: Item writes (run inside the library transaction)

-- name: LibraryLockedFields :one
-- Locks the user's item row and returns its fields. Another user's item is no row.
SELECT status, rating, notes, is_owned, finished_at, book_page, book_percent, manga_chapter, manga_volume,
    status_by_hand
FROM library_items
WHERE id = @id AND user_id = @user_id FOR UPDATE;

-- name: LibrarySetFields :exec
UPDATE library_items SET status = @status, rating = sqlc.narg(rating), notes = sqlc.narg(notes),
    is_owned = @is_owned, finished_at = sqlc.narg(finished_at), book_page = sqlc.narg(book_page),
    book_percent = sqlc.narg(book_percent), manga_chapter = sqlc.narg(manga_chapter),
    manga_volume = sqlc.narg(manga_volume),
    status_by_hand = COALESCE(sqlc.narg(status_by_hand)::boolean, status_by_hand), updated_at = now()
WHERE id = @id;

-- name: LibraryInsertItem :exec
INSERT INTO library_items (id, user_id, title_id, status, is_owned, rating, notes, added_at,
    updated_at, finished_at, book_page, book_percent, manga_chapter, manga_volume, status_by_hand)
VALUES (@id, @user_id, @title_id, @status, @is_owned, sqlc.narg(rating), sqlc.narg(notes), @added_at,
    now(), sqlc.narg(finished_at), sqlc.narg(book_page), sqlc.narg(book_percent), sqlc.narg(manga_chapter),
    sqlc.narg(manga_volume), @status_by_hand);

-- name: LibraryClearTombstone :exec
DELETE FROM library_tombstones WHERE user_id = @user_id AND library_item_id = @library_item_id;

-- name: LibraryItemTitleAndAdded :one
SELECT title_id, added_at FROM library_items WHERE id = @id;

-- name: LibraryDeleteItem :exec
DELETE FROM library_items WHERE id = @id;

-- name: LibraryWriteTombstone :exec
INSERT INTO library_tombstones (user_id, library_item_id)
VALUES (@user_id, @library_item_id)
ON CONFLICT (user_id, library_item_id) DO UPDATE SET deleted_at = now();

-- name: LibraryInsertTicks :exec
-- Episode ticks in one statement. `known` is false for imports and restores (GAM-006a).
INSERT INTO episode_progress (id, library_item_id, season, episode, watched_at_known)
SELECT (@ids::uuid[])[i], @library_item_id, (@seasons::int[])[i], (@episodes::int[])[i], @known::boolean
FROM generate_subscripts(@seasons::int[], 1) AS i
ON CONFLICT (library_item_id, season, episode) DO NOTHING;

-- name: LibraryDeleteTicks :exec
DELETE FROM episode_progress ep
USING generate_subscripts(@seasons::int[], 1) AS i
WHERE ep.library_item_id = @library_item_id AND ep.season = (@seasons::int[])[i]
  AND ep.episode = (@episodes::int[])[i];

-- name: LibraryTouchItem :exec
UPDATE library_items SET updated_at = now() WHERE id = @id;

-- name: LibraryMarkUndatedTicks :exec
-- `now()` is the transaction's start, so it picks out exactly the rows this write made.
UPDATE episode_progress SET watched_at_known = false
WHERE library_item_id = ANY(@item_ids::uuid[]) AND watched_at = now();

-- name: LibraryWatchedKeys :many
SELECT season, episode FROM episode_progress WHERE library_item_id = @library_item_id;

-- name: LibraryWatchedKeysOf :many
SELECT library_item_id, season, episode FROM episode_progress
WHERE library_item_id = ANY(@item_ids::uuid[]);

-- MARK: Journal

-- name: LibraryJournal :one
INSERT INTO actions (id, user_id, actor, kind, summary, item_ids, inverse, undo_of, agent_token_id)
VALUES (@id, @user_id, @actor, @kind, @summary, @item_ids::uuid[], @inverse, sqlc.narg(undo_of),
    sqlc.narg(agent_token_id))
RETURNING created_at;

-- name: LibraryLockAction :one
SELECT summary, inverse, item_ids, undone_at FROM actions
WHERE id = @id AND user_id = @user_id FOR UPDATE;

-- name: LibraryMarkUndone :exec
UPDATE actions SET undone_at = now() WHERE id = @id;

-- name: LibraryActions :many
SELECT a.id, a.actor, a.kind, a.summary, a.item_ids, a.created_at, a.undone_at, a.undo_of,
       t.name AS agent_name
FROM actions a LEFT JOIN agent_tokens t ON t.id = a.agent_token_id
WHERE a.user_id = @user_id
ORDER BY a.created_at DESC, a.id DESC LIMIT @row_limit;

-- MARK: Reads

-- name: LibraryTombstonesSince :many
SELECT library_item_id FROM library_tombstones
WHERE user_id = @user_id AND deleted_at > @since;

-- name: LibraryImportStates :many
SELECT id, title_id, status, rating, notes, is_owned, finished_at, book_page, book_percent, manga_chapter,
    manga_volume, status_by_hand
FROM library_items
WHERE user_id = @user_id AND title_id = ANY(@title_ids::uuid[]);

-- name: LibraryStatusByHand :many
SELECT status_by_hand FROM library_items WHERE id = @id;

-- name: LibraryReopenAired :execrows
-- A finished show goes back to in progress once a regular episode it has not ticked airs after it
-- was finished: a new season, or the next episode of a running show (owner, 2026-10-30). Only
-- airings since `since` count, so an old gap in an imported show never reopens it.
UPDATE library_items li
SET status = 'in_progress', finished_at = NULL, updated_at = sqlc.arg(now)
WHERE li.status = 'finished' AND li.finished_at IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM show_episodes se
    WHERE se.title_id = li.title_id AND se.season > 0
      AND se.airs_at > li.finished_at
      AND se.airs_at > sqlc.arg(since) AND se.airs_at <= sqlc.arg(now)
      AND NOT EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
                      AND ep.season = se.season AND ep.episode = se.episode));
