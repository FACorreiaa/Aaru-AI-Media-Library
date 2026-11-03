-- Worker backoff (Go audit REL-005, REL-006, DB-008).
--
-- mal_connections: a connection whose push keeps failing (MAL down, rate limited) waits longer
-- each time instead of being retried every 30 seconds.
-- user_progress: a user whose badge evaluation keeps failing waits longer each time, and after a
-- few failures waits for their next write instead of being retried forever.
-- user_progress_fresh: the worker's claim of never-evaluated users can use an index.

-- +goose Up
ALTER TABLE mal_connections
    ADD COLUMN push_failures integer NOT NULL DEFAULT 0,
    ADD COLUMN push_not_before timestamp with time zone;

ALTER TABLE user_progress
    ADD COLUMN eval_failures integer NOT NULL DEFAULT 0,
    ADD COLUMN eval_not_before timestamp with time zone;

CREATE INDEX user_progress_fresh ON user_progress USING btree (user_id) WHERE (evaluated_at IS NULL);

-- +goose Down
DROP INDEX IF EXISTS user_progress_fresh;

ALTER TABLE user_progress
    DROP COLUMN IF EXISTS eval_not_before,
    DROP COLUMN IF EXISTS eval_failures;

ALTER TABLE mal_connections
    DROP COLUMN IF EXISTS push_not_before,
    DROP COLUMN IF EXISTS push_failures;
