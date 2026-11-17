-- Worlds for libraries that existed before Worlds did (GRAPH-007). A title's World is queued when
-- the title is added by hand or an import is applied, so without this an existing account's
-- Worlds page stays empty until its owner adds something. Every title in anyone's library that
-- was never looked at is queued once, at the import priority (0): behind any title someone opens.
-- The worker builds one at a time at the providers' pace, so a large backlog takes hours, not a
-- burst.

-- +goose Up
INSERT INTO world_builds (title_id, priority, state, attempts, run_after, created_at)
SELECT DISTINCT li.title_id, 0, 'queued', 0, now(), now()
FROM library_items li
ON CONFLICT (title_id) DO NOTHING;

-- +goose Down
-- Nothing to undo: the queue is dropped with its table (00017).
SELECT 1;
