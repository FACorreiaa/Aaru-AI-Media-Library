-- `@aaru` answers in one channel per group, #ai-reply, not in the channel it was tagged in
-- (owner 2026-11-14: in a 15-person group, answers everywhere were noise). The channel is a plain
-- text channel made on the first mention and found by its flag, never by its name, so a rename
-- keeps it. A group has at most one.
--
-- An answer to a mention in a title channel keeps its spoiler stamp, but #ai-reply is about no
-- title, so the message records which title its stamp is about.

-- +goose Up
ALTER TABLE group_channels ADD COLUMN is_agent_replies boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX group_channels_one_agent_replies ON group_channels USING btree (group_id) WHERE is_agent_replies;
ALTER TABLE group_messages ADD COLUMN spoiler_title_id uuid;

-- +goose Down
ALTER TABLE group_messages DROP COLUMN spoiler_title_id;
DROP INDEX group_channels_one_agent_replies;
ALTER TABLE group_channels DROP COLUMN is_agent_replies;
