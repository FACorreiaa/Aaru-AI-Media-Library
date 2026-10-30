-- Import jobs as a leased queue (JOB-001) plus their parsed rows (IMP-001).
-- PostgresImportJobStore.swift.

-- name: ImportJobInsert :exec
INSERT INTO import_jobs (id, user_id, source, state, stats, error_summary, filename, created_at, updated_at)
VALUES (@id, @user_id, @source, @state, @stats, @error_summary, @filename, @created_at, @updated_at);

-- name: ImportJobUpdate :exec
UPDATE import_jobs SET state = @state, stats = @stats, error_summary = @error_summary, updated_at = @updated_at,
    locked_until = NULL
WHERE id = @id AND user_id = @user_id;

-- name: ImportJobGet :one
SELECT id, user_id, source, state, stats, error_summary, filename, created_at, updated_at, attempts, rows_matched,
    action_id,
    (SELECT count(*)::integer FROM import_rows r WHERE r.job_id = import_jobs.id) AS rows_total,
    (SELECT count(*)::integer FROM import_listens l WHERE l.job_id = import_jobs.id) AS listens_staged
FROM import_jobs WHERE id = @id AND user_id = @user_id;

-- name: ImportJobsByUser :many
SELECT id, user_id, source, state, stats, error_summary, filename, created_at, updated_at, attempts, rows_matched,
    action_id,
    (SELECT count(*)::integer FROM import_rows r WHERE r.job_id = import_jobs.id) AS rows_total,
    (SELECT count(*)::integer FROM import_listens l WHERE l.job_id = import_jobs.id) AS listens_staged
FROM import_jobs WHERE user_id = @user_id
ORDER BY created_at DESC LIMIT @row_limit;

-- name: ImportJobClaim :one
-- One statement: SKIP LOCKED means two workers never lease the same job.
UPDATE import_jobs SET state = 'running', attempts = attempts + 1, rows_matched = 0,
    locked_until = @locked_until, updated_at = @now
WHERE id = (
    SELECT j.id FROM import_jobs j
    WHERE ((j.state = 'queued' AND (j.locked_until IS NULL OR j.locked_until <= @now))
       OR (j.state = 'running' AND j.locked_until < @now))
      AND (sqlc.narg(owner)::uuid IS NULL OR j.user_id = sqlc.narg(owner)::uuid)
    ORDER BY j.created_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1
)
RETURNING id, user_id, source, state, stats, error_summary, filename, created_at, updated_at, attempts, rows_matched,
    action_id,
    (SELECT count(*)::integer FROM import_rows r WHERE r.job_id = import_jobs.id) AS rows_total,
    (SELECT count(*)::integer FROM import_listens l WHERE l.job_id = import_jobs.id) AS listens_staged;

-- name: ImportJobRetry :exec
UPDATE import_jobs SET state = 'queued', error_summary = @error_summary, locked_until = @not_before,
    updated_at = @now
WHERE id = @id;

-- name: ImportJobRelease :exec
UPDATE import_jobs SET state = 'queued', attempts = greatest(attempts - 1, 0), locked_until = NULL,
    rows_matched = 0, updated_at = @now
WHERE id = @id AND state = 'running';

-- name: ImportJobProgress :exec
UPDATE import_jobs SET rows_matched = @rows_matched, locked_until = @locked_until
WHERE id = @id AND state = 'running';

-- name: ImportJobSavePlan :exec
UPDATE import_jobs SET state = @state, stats = @stats, error_summary = @error_summary, updated_at = @updated_at,
    locked_until = NULL, action_id = coalesce(sqlc.narg(action_id)::uuid, action_id)
WHERE id = @id;

-- name: ImportJobDelete :one
DELETE FROM import_jobs WHERE id = @id AND user_id = @user_id RETURNING id;

-- name: ImportRowsInsert :exec
-- A few hundred rows per statement: a 2,000-row export is a handful of round trips, not 2,000.
INSERT INTO import_rows (job_id, idx, row)
SELECT @job_id::uuid, unnest(@idx::integer[]), unnest(@rows::jsonb[]);

-- name: ImportRows :many
SELECT idx, row, outcome, reason, title_id FROM import_rows WHERE job_id = @job_id ORDER BY idx;

-- name: ImportRowCount :one
SELECT count(*)::integer FROM import_rows WHERE job_id = @job_id;

-- MARK: Stremio link codes

-- name: StremioLinkSweep :exec
DELETE FROM stremio_link_requests WHERE expires_at < @now;

-- name: StremioLinkCreate :exec
INSERT INTO stremio_link_requests (code, user_id, expires_at) VALUES (@code, @user_id, @expires_at)
ON CONFLICT (code) DO UPDATE SET user_id = EXCLUDED.user_id, expires_at = EXCLUDED.expires_at;

-- name: StremioLinkExpiry :many
SELECT expires_at FROM stremio_link_requests WHERE code = @code AND user_id = @user_id;

-- name: StremioLinkConsume :many
DELETE FROM stremio_link_requests WHERE code = @code AND user_id = @user_id RETURNING code;
