-- Files in a chat with Aaru (ASK-010): one row per file the user attached, checked by
-- internal/upload before it was stored. A file is kept for at most an hour, so a follow-up turn can
-- still hand it to an import, then swept; deleting the chat or the account deletes it with them.
-- `kind` is what the chat does with it: a picture, PDF or text goes to the model, an export or a
-- listening history only as a summary (`source`, `rows`).

-- +goose Up
CREATE TABLE chat_attachments (
    id uuid PRIMARY KEY,
    chat_id uuid NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('image', 'pdf', 'text', 'export', 'listens')),
    name text NOT NULL,
    media_type text NOT NULL,
    source text,
    rows integer,
    data bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX chat_attachments_chat ON chat_attachments (chat_id, created_at);
CREATE INDEX chat_attachments_user ON chat_attachments (user_id);
CREATE INDEX chat_attachments_created ON chat_attachments (created_at);

-- +goose Down
DROP TABLE IF EXISTS chat_attachments;
