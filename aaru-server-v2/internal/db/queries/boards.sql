-- The friends-only Board: posts, upvotes and comments (BOARD-001, PostgresBoardStore.swift).
-- Every post read selects the same columns, so internal/boards converts each row type to one.
-- Deleted posts are filtered by each read's WHERE.

-- name: BoardInsertPost :exec
INSERT INTO board_posts (id, user_id, title_id, rating, body, spoiler_season, spoiler_episode, spoiler_ending, created_at)
VALUES (sqlc.arg(id), sqlc.arg(user_id), sqlc.narg(title_id), sqlc.narg(rating)::float8, sqlc.arg(body),
        sqlc.narg(spoiler_season), sqlc.narg(spoiler_episode), sqlc.arg(spoiler_ending), sqlc.arg(created_at));

-- name: BoardPost :one
-- Nil when the post is unknown or deleted.
SELECT b.id, b.user_id, p.handle, u.display_name, u.avatar_version, b.title_id, b.rating, b.body,
    b.spoiler_season, b.spoiler_episode, b.spoiler_ending, b.created_at, b.edited_at,
    (SELECT count(*)::int FROM board_upvotes v WHERE v.post_id = b.id)::int AS upvotes,
    EXISTS (SELECT 1 FROM board_upvotes v WHERE v.post_id = b.id AND v.user_id = sqlc.arg(viewer)::uuid)
        AS upvoted_by_viewer,
    (SELECT count(*)::int FROM board_comments c WHERE c.post_id = b.id AND c.deleted_at IS NULL)::int
        AS comment_count
FROM board_posts b
JOIN profiles p ON p.user_id = b.user_id JOIN users u ON u.id = b.user_id
WHERE b.id = sqlc.arg(id) AND b.deleted_at IS NULL;

-- name: BoardFeed :many
-- Posts by these authors, newest first, keyset-paged by the id of the last post seen.
SELECT b.id, b.user_id, p.handle, u.display_name, u.avatar_version, b.title_id, b.rating, b.body,
    b.spoiler_season, b.spoiler_episode, b.spoiler_ending, b.created_at, b.edited_at,
    (SELECT count(*)::int FROM board_upvotes v WHERE v.post_id = b.id)::int AS upvotes,
    EXISTS (SELECT 1 FROM board_upvotes v WHERE v.post_id = b.id AND v.user_id = sqlc.arg(viewer)::uuid)
        AS upvoted_by_viewer,
    (SELECT count(*)::int FROM board_comments c WHERE c.post_id = b.id AND c.deleted_at IS NULL)::int
        AS comment_count
FROM board_posts b
JOIN profiles p ON p.user_id = b.user_id JOIN users u ON u.id = b.user_id
WHERE b.user_id = ANY(sqlc.arg(authors)::uuid[]) AND b.deleted_at IS NULL
  AND (sqlc.narg(before)::uuid IS NULL
       OR (b.created_at, b.id) < (SELECT bp.created_at, bp.id FROM board_posts bp WHERE bp.id = sqlc.narg(before)::uuid))
ORDER BY b.created_at DESC, b.id DESC
LIMIT sqlc.arg(row_limit);

-- name: BoardTop :many
-- Posts by these authors created since `since`: upvotes descending, then newest.
SELECT b.id, b.user_id, p.handle, u.display_name, u.avatar_version, b.title_id, b.rating, b.body,
    b.spoiler_season, b.spoiler_episode, b.spoiler_ending, b.created_at, b.edited_at,
    (SELECT count(*)::int FROM board_upvotes v WHERE v.post_id = b.id)::int AS upvotes,
    EXISTS (SELECT 1 FROM board_upvotes v WHERE v.post_id = b.id AND v.user_id = sqlc.arg(viewer)::uuid)
        AS upvoted_by_viewer,
    (SELECT count(*)::int FROM board_comments c WHERE c.post_id = b.id AND c.deleted_at IS NULL)::int
        AS comment_count
FROM board_posts b
JOIN profiles p ON p.user_id = b.user_id JOIN users u ON u.id = b.user_id
WHERE b.user_id = ANY(sqlc.arg(authors)::uuid[]) AND b.deleted_at IS NULL
  AND b.created_at >= sqlc.arg(since)::pg_catalog.timestamptz
ORDER BY upvotes DESC, b.created_at DESC, b.id DESC
LIMIT sqlc.arg(row_limit);

-- name: BoardTitlePosts :many
-- Posts about one title by these authors, newest first.
SELECT b.id, b.user_id, p.handle, u.display_name, u.avatar_version, b.title_id, b.rating, b.body,
    b.spoiler_season, b.spoiler_episode, b.spoiler_ending, b.created_at, b.edited_at,
    (SELECT count(*)::int FROM board_upvotes v WHERE v.post_id = b.id)::int AS upvotes,
    EXISTS (SELECT 1 FROM board_upvotes v WHERE v.post_id = b.id AND v.user_id = sqlc.arg(viewer)::uuid)
        AS upvoted_by_viewer,
    (SELECT count(*)::int FROM board_comments c WHERE c.post_id = b.id AND c.deleted_at IS NULL)::int
        AS comment_count
FROM board_posts b
JOIN profiles p ON p.user_id = b.user_id JOIN users u ON u.id = b.user_id
WHERE b.title_id = sqlc.arg(title_id) AND b.user_id = ANY(sqlc.arg(authors)::uuid[]) AND b.deleted_at IS NULL
ORDER BY b.created_at DESC, b.id DESC
LIMIT sqlc.arg(row_limit);

-- name: BoardEditPost :exec
UPDATE board_posts SET body = sqlc.arg(body), edited_at = sqlc.arg(now)::pg_catalog.timestamptz
WHERE id = sqlc.arg(id) AND deleted_at IS NULL;

-- name: BoardDeletePost :exec
-- Soft delete: the post vanishes from every read.
UPDATE board_posts SET deleted_at = sqlc.arg(now)::pg_catalog.timestamptz WHERE id = sqlc.arg(id) AND deleted_at IS NULL;

-- name: BoardUpvote :exec
INSERT INTO board_upvotes (post_id, user_id) VALUES (sqlc.arg(post_id), sqlc.arg(user_id))
ON CONFLICT DO NOTHING;

-- name: BoardRemoveUpvote :exec
DELETE FROM board_upvotes WHERE post_id = sqlc.arg(post_id) AND user_id = sqlc.arg(user_id);

-- name: BoardUpvoters :many
SELECT v.user_id, p.handle, u.display_name, u.avatar_version
FROM board_upvotes v JOIN profiles p ON p.user_id = v.user_id JOIN users u ON u.id = v.user_id
WHERE v.post_id = $1 ORDER BY v.created_at, v.user_id;

-- name: BoardInsertComment :exec
INSERT INTO board_comments (id, post_id, user_id, author_kind, reply_to, body, mentions, mentions_agent, created_at)
VALUES (sqlc.arg(id), sqlc.arg(post_id), sqlc.narg(user_id), sqlc.arg(author_kind), sqlc.narg(reply_to),
        sqlc.arg(body), sqlc.arg(mentions)::uuid[], sqlc.arg(mentions_agent), sqlc.arg(created_at));

-- name: BoardComment :one
SELECT c.id, c.post_id, c.user_id, p.handle, u.display_name, u.avatar_version, c.author_kind, c.reply_to, c.body,
    c.mentions, c.mentions_agent, c.created_at, c.deleted_at
FROM board_comments c
LEFT JOIN profiles p ON p.user_id = c.user_id LEFT JOIN users u ON u.id = c.user_id
WHERE c.id = sqlc.arg(id) AND c.post_id = sqlc.arg(post_id);

-- name: BoardComments :many
-- Oldest first. Includes deleted comments; the service filters them.
SELECT c.id, c.post_id, c.user_id, p.handle, u.display_name, u.avatar_version, c.author_kind, c.reply_to, c.body,
    c.mentions, c.mentions_agent, c.created_at, c.deleted_at
FROM board_comments c
LEFT JOIN profiles p ON p.user_id = c.user_id LEFT JOIN users u ON u.id = c.user_id
WHERE c.post_id = sqlc.arg(post_id)
  AND (sqlc.narg(after)::uuid IS NULL
       OR (c.created_at, c.id) > (SELECT bc.created_at, bc.id FROM board_comments bc WHERE bc.id = sqlc.narg(after)::uuid))
ORDER BY c.created_at, c.id
LIMIT sqlc.arg(row_limit);

-- name: BoardDeleteComment :exec
-- Soft delete.
UPDATE board_comments SET deleted_at = sqlc.arg(now)::pg_catalog.timestamptz WHERE id = sqlc.arg(id) AND deleted_at IS NULL;
