import FluentKit
import FluentSQL

/// JOB-001, IMP-001, IMP-005 · imports run as leased jobs and produce a plan before any write.
/// `import_rows` holds the parsed rows (never the uploaded file) and what the plan does with each.
struct AddImportPlans: SQLMigration {
    let forward = [
        "ALTER TABLE import_jobs DROP CONSTRAINT import_jobs_state_check",
        """
        ALTER TABLE import_jobs ADD CONSTRAINT import_jobs_state_check
            CHECK (state IN ('queued', 'running', 'planned', 'succeeded', 'failed', 'partial'))
        """,
        "ALTER TABLE import_jobs ADD COLUMN filename text",
        "ALTER TABLE import_jobs ADD COLUMN attempts integer NOT NULL DEFAULT 0",
        "ALTER TABLE import_jobs ADD COLUMN locked_until timestamptz",
        "CREATE INDEX import_jobs_claim ON import_jobs (state, locked_until, created_at)",
        """
        CREATE TABLE import_rows (
            job_id uuid NOT NULL REFERENCES import_jobs(id) ON DELETE CASCADE,
            idx integer NOT NULL,
            row jsonb NOT NULL,
            outcome text NOT NULL DEFAULT 'pending'
                CHECK (outcome IN ('pending', 'create', 'update', 'skip', 'unmatched')),
            reason text,
            title_id uuid REFERENCES titles(id) ON DELETE SET NULL,
            PRIMARY KEY (job_id, idx)
        )
        """,
    ]
    let backward = [
        "DROP TABLE import_rows",
        "DROP INDEX import_jobs_claim",
        "ALTER TABLE import_jobs DROP COLUMN locked_until",
        "ALTER TABLE import_jobs DROP COLUMN attempts",
        "ALTER TABLE import_jobs DROP COLUMN filename",
        "ALTER TABLE import_jobs DROP CONSTRAINT import_jobs_state_check",
        """
        ALTER TABLE import_jobs ADD CONSTRAINT import_jobs_state_check
            CHECK (state IN ('queued', 'running', 'succeeded', 'failed', 'partial'))
        """,
    ]
}

/// IMP-002 · Trakt connect: one connection per user (tokens encrypted with TRAKT_TOKEN_KEY), and
/// the short-lived PKCE requests a sign-in round trip carries. Both go with the user.
struct CreateTraktConnections: SQLMigration {
    let forward = [
        """
        CREATE TABLE trakt_connections (
            user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            access_token text NOT NULL,
            refresh_token text NOT NULL,
            expires_at timestamptz NOT NULL,
            username text,
            connected_at timestamptz NOT NULL DEFAULT now()
        )
        """,
        """
        CREATE TABLE trakt_auth_requests (
            state_hash text PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            code_verifier text NOT NULL,
            return_to text NOT NULL,
            expires_at timestamptz NOT NULL
        )
        """,
    ]
    let backward = ["DROP TABLE trakt_auth_requests", "DROP TABLE trakt_connections"]
}
