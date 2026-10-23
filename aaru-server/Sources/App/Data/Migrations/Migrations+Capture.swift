import FluentKit
import FluentSQL

/// AG-006 · capture as an import source. `capture_inputs` holds what the user sent (text, or one
/// image) only until the worker has read the titles out of it: deleted then, and by the sweep an
/// hour after in any case. No foreign key to the job: the input is written first, and an input
/// whose job never landed is the sweep's. `agent_usage.cost_micros` meters model spend per user and
/// day in millionths of a dollar (AG-007's groundwork).
struct AddCapture: SQLMigration {
    let forward = [
        """
        CREATE TABLE capture_inputs (
            job_id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            kind text NOT NULL CHECK (kind IN ('text', 'image')),
            text text,
            image bytea,
            media_type text,
            created_at timestamptz NOT NULL
        )
        """,
        "CREATE INDEX capture_inputs_created ON capture_inputs (created_at)",
        "CREATE INDEX import_jobs_capture ON import_jobs (user_id, created_at) WHERE source = 'capture'",
        "ALTER TABLE agent_usage ADD COLUMN cost_micros bigint NOT NULL DEFAULT 0",
    ]
    let backward = [
        "ALTER TABLE agent_usage DROP COLUMN cost_micros",
        "DROP INDEX import_jobs_capture",
        "DROP TABLE capture_inputs",
    ]
}
