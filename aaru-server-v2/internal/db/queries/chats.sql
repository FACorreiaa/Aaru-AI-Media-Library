-- name: CreateChat :exec
INSERT INTO chats (id, user_id) VALUES ($1, $2);

-- name: GetChat :one
-- Someone else's chat is no row, same as a missing one.
SELECT id, user_id, title, created_at, updated_at FROM chats WHERE id = $1 AND user_id = $2;

-- name: SetChatTitle :exec
-- Only a chat's first turn names it.
UPDATE chats SET title = sqlc.arg(title)::text WHERE id = sqlc.arg(id)::uuid AND title IS NULL;

-- name: FailStaleChatTurns :exec
-- An agent turn that streamed past the cutoff lost its process: it fails so the chat is free.
UPDATE chat_turns SET state = 'failed', updated_at = sqlc.arg(now)::pg_catalog.timestamptz
WHERE chat_id = sqlc.arg(chat_id)::uuid AND state = 'streaming'
  AND updated_at < sqlc.arg(cutoff)::pg_catalog.timestamptz;

-- name: BeginChatTurn :one
-- One statement, so the unique index on a streaming turn refuses the pair whole, and the day's count
-- with it. The user turn is stored done, the agent turn streaming. No row when the chat is not the
-- user's.
WITH mine AS (
    SELECT id FROM chats WHERE id = sqlc.arg(chat_id)::uuid AND user_id = sqlc.arg(user_id)::uuid
), u AS (
    INSERT INTO chat_turns (id, chat_id, user_id, role, body, state, created_at, updated_at)
    SELECT sqlc.arg(user_turn)::uuid, mine.id, sqlc.arg(user_id)::uuid, 'user', sqlc.arg(body)::text, 'done',
        sqlc.arg(now)::pg_catalog.timestamptz, sqlc.arg(now)::pg_catalog.timestamptz
    FROM mine
    RETURNING id
), a AS (
    INSERT INTO chat_turns (id, chat_id, user_id, role, state, created_at, updated_at)
    SELECT sqlc.arg(agent_turn)::uuid, mine.id, sqlc.arg(user_id)::uuid, 'agent', 'streaming',
        sqlc.arg(now)::pg_catalog.timestamptz, sqlc.arg(now)::pg_catalog.timestamptz
    FROM mine
    RETURNING id
), touched AS (
    UPDATE chats SET updated_at = sqlc.arg(now)::pg_catalog.timestamptz WHERE id IN (SELECT id FROM mine)
    RETURNING id
), counted AS (
    INSERT INTO agent_usage (user_id, day, chat_turns)
    SELECT sqlc.arg(user_id)::uuid, (sqlc.arg(now)::pg_catalog.timestamptz AT TIME ZONE 'UTC')::date, 1 FROM mine
    ON CONFLICT (user_id, day) DO UPDATE SET chat_turns = agent_usage.chat_turns + 1
    RETURNING user_id
)
SELECT (SELECT count(*) FROM u)::int AS stored;

-- name: FinishChatTurn :execrows
-- Only a streaming turn finishes: one already failed as stale stays failed.
UPDATE chat_turns SET state = sqlc.arg(state)::text, body = sqlc.arg(body)::text,
    components = sqlc.narg(components)::jsonb, updated_at = sqlc.arg(now)::pg_catalog.timestamptz
WHERE id = sqlc.arg(id)::uuid AND state = 'streaming';

-- name: RecentChatTurns :many
SELECT id, chat_id, role, body, components, state, created_at
FROM (
    SELECT id, chat_id, role, body, components, state, created_at FROM chat_turns
    WHERE chat_id = $1 ORDER BY created_at DESC, role DESC LIMIT $2
) t ORDER BY created_at, role DESC;

-- name: ChatRepliesToday :one
-- What counts toward the daily cap shared with @aaru: replies whose model was, or will be, called
-- (the states GroupAgentLoad counts), plus the turns the user sent today. That is the counter, not
-- the rows: deleting chats must not hand the day's sends back.
SELECT (
    (SELECT count(*) FROM agent_replies a WHERE a.tagger_id = sqlc.arg(user_id)::uuid
        AND a.created_at >= sqlc.arg(day_start)::pg_catalog.timestamptz
        AND a.state IN ('queued', 'running', 'done', 'failed'))
    + COALESCE((SELECT u.chat_turns FROM agent_usage u WHERE u.user_id = sqlc.arg(user_id)::uuid
        AND u.day = (sqlc.arg(day_start)::pg_catalog.timestamptz AT TIME ZONE 'UTC')::date), 0)
)::bigint AS replies;

-- name: DeleteAllChats :exec
DELETE FROM chats WHERE user_id = $1;

-- name: ChatsForExport :many
SELECT id, user_id, title, created_at, updated_at FROM chats WHERE user_id = $1 ORDER BY created_at, id;

-- name: ChatTurnsForExport :many
SELECT id, chat_id, role, body, components, state, created_at FROM chat_turns
WHERE user_id = $1 ORDER BY chat_id, created_at, role DESC;

-- name: InProgressTitleNames :many
-- What the user is in the middle of, latest first: the names a spoken question is likely to use.
SELECT t.title FROM library_items li
JOIN titles t ON t.id = li.title_id
WHERE li.user_id = $1 AND li.status = 'in_progress'
ORDER BY li.updated_at DESC, li.id
LIMIT $2;
