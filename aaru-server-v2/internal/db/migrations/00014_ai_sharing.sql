-- AI sharing: a user's yes or no to Aaru sending their data to its AI provider, and when they
-- answered. NULL is unanswered, which counts as no. Every account made before this shipped starts
-- unanswered and is asked once.

-- +goose Up
ALTER TABLE users
    ADD COLUMN ai_sharing_allowed boolean,
    ADD COLUMN ai_sharing_decided_at timestamptz;

-- +goose Down
ALTER TABLE users
    DROP COLUMN ai_sharing_decided_at,
    DROP COLUMN ai_sharing_allowed;
