-- Indexes for account deletion and the listen resolver (Go audit DB-005, DB-006).
--
-- DB-005: deleting a user cascades to their actions, and each deleted action runs ON DELETE SET
-- NULL on these columns. Without a leading index every one is a scan of a platform-wide table:
-- measured on 205k actions, deleting a user with 5k of them took 134 s, and 0.6 s with these.
--
-- listens(agent_token_id) is left out on purpose. Nearly every scrobbled listen carries it, so it
-- costs on every insert (100k inserts went from about 6 s to about 16 s), and it did not speed up
-- the rare token delete (about 1.4 s either way on 800k listens).
--
-- DB-006: listens_unresolved_key lets the resolver read the distinct unresolved tracks from an
-- index-only scan: 5.2 s and 613k buffers a pass became 0.5 s and 18k on 600k unresolved listens.
--
-- CONCURRENTLY so a deploy does not block writes. A failed build leaves an INVALID index that IF
-- NOT EXISTS would then skip: drop it by hand before running the migration again.

-- +goose NO TRANSACTION

-- +goose Up
CREATE INDEX CONCURRENTLY IF NOT EXISTS points_events_action ON points_events USING btree (action_id) WHERE (action_id IS NOT NULL);
CREATE INDEX CONCURRENTLY IF NOT EXISTS user_badges_action ON user_badges USING btree (action_id) WHERE (action_id IS NOT NULL);
CREATE INDEX CONCURRENTLY IF NOT EXISTS import_jobs_action ON import_jobs USING btree (action_id) WHERE (action_id IS NOT NULL);
CREATE INDEX CONCURRENTLY IF NOT EXISTS agent_plans_action ON agent_plans USING btree (action_id) WHERE (action_id IS NOT NULL);
CREATE INDEX CONCURRENTLY IF NOT EXISTS actions_undo_of ON actions USING btree (undo_of) WHERE (undo_of IS NOT NULL);
CREATE INDEX CONCURRENTLY IF NOT EXISTS tonight_feedback_item ON tonight_feedback USING btree (library_item_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS listens_unresolved_key ON listens USING btree (track_key, (lower(coalesce(album, '')))) INCLUDE (album) WHERE (release_group_mbid IS NULL);

-- +goose Down
DROP INDEX CONCURRENTLY IF EXISTS listens_unresolved_key;
DROP INDEX CONCURRENTLY IF EXISTS tonight_feedback_item;
DROP INDEX CONCURRENTLY IF EXISTS actions_undo_of;
DROP INDEX CONCURRENTLY IF EXISTS agent_plans_action;
DROP INDEX CONCURRENTLY IF EXISTS import_jobs_action;
DROP INDEX CONCURRENTLY IF EXISTS user_badges_action;
DROP INDEX CONCURRENTLY IF EXISTS points_events_action;
