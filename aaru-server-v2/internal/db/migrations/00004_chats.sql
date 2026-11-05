-- Chats with Aaru (ASK-009): a chat is a user's own thread, a chat turn one user or Aaru entry in
-- it. Only an agent turn is ever `streaming`, and at most one per chat (the partial unique index).
-- Plans the chat proposes can spend one of the user's captures (`spends_capture`).
-- `agent_usage.chat_turns` is what the daily cap reads: unlike the turns, it outlives deleting chats.

-- +goose Up
CREATE TABLE chats (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX chats_user ON chats (user_id, updated_at DESC);
CREATE TABLE chat_turns (
    id uuid PRIMARY KEY,
    chat_id uuid NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role text NOT NULL CHECK (role IN ('user', 'agent')),
    body text NOT NULL DEFAULT '',
    components jsonb,
    state text NOT NULL CHECK (state IN ('streaming', 'done', 'failed', 'stopped')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX chat_turns_chat ON chat_turns (chat_id, created_at);
CREATE INDEX chat_turns_user ON chat_turns (user_id);
CREATE UNIQUE INDEX chat_turns_one_streaming ON chat_turns (chat_id) WHERE state = 'streaming';
ALTER TABLE agent_plans ADD COLUMN spends_capture boolean NOT NULL DEFAULT false;
ALTER TABLE agent_usage ADD COLUMN chat_turns integer NOT NULL DEFAULT 0;

-- +goose Down
ALTER TABLE agent_usage DROP COLUMN IF EXISTS chat_turns;
ALTER TABLE agent_plans DROP COLUMN IF EXISTS spends_capture;
DROP TABLE IF EXISTS chat_turns;
DROP TABLE IF EXISTS chats;
