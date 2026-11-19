-- Web searches the assistant ran for a user on a day (ASK-004). They are billed apart from tokens
-- (already in cost_micros), and this count is what the daily search cap reads.

-- +goose Up
ALTER TABLE agent_usage ADD COLUMN web_searches integer NOT NULL DEFAULT 0;

-- +goose Down
ALTER TABLE agent_usage DROP COLUMN IF EXISTS web_searches;
