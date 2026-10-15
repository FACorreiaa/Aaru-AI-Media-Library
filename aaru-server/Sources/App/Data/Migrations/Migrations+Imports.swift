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

/// Airing-episode pushes (2026-10-15 decision): devices with their APNs environment (TestFlight and
/// App Store builds are `production`, Xcode runs are `sandbox`), the opt-in, and one row per
/// episode already announced so nobody hears about an episode twice.
struct CreatePush: SQLMigration {
    let forward = [
        """
        CREATE TABLE apns_devices (
            token text PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            environment text NOT NULL CHECK (environment IN ('sandbox', 'production')),
            topic text NOT NULL,
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """,
        "CREATE INDEX apns_devices_user ON apns_devices (user_id)",
        """
        CREATE TABLE notification_settings (
            user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            airing boolean NOT NULL DEFAULT false,
            airing_since timestamptz
        )
        """,
        """
        CREATE TABLE notifications_sent (
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            title_id uuid NOT NULL REFERENCES titles(id) ON DELETE CASCADE,
            season integer NOT NULL,
            episode integer NOT NULL,
            sent_at timestamptz NOT NULL DEFAULT now(),
            PRIMARY KEY (user_id, title_id, season, episode)
        )
        """,
    ]
    let backward = ["DROP TABLE notifications_sent", "DROP TABLE notification_settings", "DROP TABLE apns_devices"]
}

/// AUTH-005 · Google joins the sign-in providers.
struct AddGoogleProvider: SQLMigration {
    let forward = [
        "ALTER TABLE auth_identities DROP CONSTRAINT auth_identities_provider_check",
        """
        ALTER TABLE auth_identities ADD CONSTRAINT auth_identities_provider_check
            CHECK (provider IN ('apple', 'email', 'google'))
        """,
    ]
    let backward = [
        "ALTER TABLE auth_identities DROP CONSTRAINT auth_identities_provider_check",
        """
        ALTER TABLE auth_identities ADD CONSTRAINT auth_identities_provider_check
            CHECK (provider IN ('apple', 'email'))
        """,
    ]
}

/// APP-010 · the week grid's cell banner and network, whether an episode's air time is exact
/// (AniList) or a date (TMDB), and the episode synopsis the calendar's detail panel shows. Shows are marked unhydrated
/// so the next refresh fills the
/// new columns for titles already in libraries.
struct AddTitleArtwork: SQLMigration {
    let forward = [
        "ALTER TABLE titles ADD COLUMN backdrop_url text",
        "ALTER TABLE titles ADD COLUMN network text",
        "ALTER TABLE show_episodes ADD COLUMN airs_at_exact boolean NOT NULL DEFAULT false",
        "ALTER TABLE show_episodes ADD COLUMN overview text",
        "UPDATE titles SET episodes_hydrated_at = NULL WHERE type = 'show'",
    ]
    let backward = [
        "ALTER TABLE show_episodes DROP COLUMN overview",
        "ALTER TABLE show_episodes DROP COLUMN airs_at_exact",
        "ALTER TABLE titles DROP COLUMN network",
        "ALTER TABLE titles DROP COLUMN backdrop_url",
    ]
}
