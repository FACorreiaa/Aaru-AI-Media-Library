-- The leased queues' backlog for `/metrics` (Go audit REL-004): jobs waiting to be claimed and how
-- long the oldest has waited. Both read the queue indexes (state first).

-- name: WorkerQueueStats :many
SELECT 'import_jobs'::text AS queue, count(*)::bigint AS depth,
    coalesce(extract(epoch FROM (sqlc.arg(now)::pg_catalog.timestamptz - min(j.created_at))), 0)::float8
        AS oldest_age_seconds
FROM import_jobs j WHERE j.state = 'queued'
UNION ALL
SELECT 'agent_replies'::text, count(*)::bigint,
    coalesce(extract(epoch FROM (sqlc.arg(now)::pg_catalog.timestamptz - min(a.created_at))), 0)::float8
FROM agent_replies a WHERE a.state = 'queued';
