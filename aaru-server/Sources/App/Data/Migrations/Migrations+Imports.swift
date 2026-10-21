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

/// GAM-006a · whether an episode tick's `watched_at` is when the user watched it. Imports and
/// restores (undoing a delete) re-create ticks at write time, so they are marked unknown and
/// the recap leaves them out. Rows written before this migration are backfilled by matching
/// their `watched_at` to the import or undo action of the same transaction: both are `now()`.
struct AddEpisodeWatchDateKnown: SQLMigration {
    let forward = [
        "ALTER TABLE episode_progress ADD COLUMN watched_at_known boolean NOT NULL DEFAULT true",
        """
        UPDATE episode_progress ep SET watched_at_known = false
        FROM library_items li, actions a
        WHERE li.id = ep.library_item_id AND a.user_id = li.user_id
          AND a.kind IN ('import', 'undo') AND a.created_at = ep.watched_at
        """,
        "CREATE INDEX episode_progress_item_watched ON episode_progress (library_item_id, watched_at)",
    ]
    let backward = [
        "DROP INDEX episode_progress_item_watched",
        "ALTER TABLE episode_progress DROP COLUMN watched_at_known",
    ]
}

/// A1 · episode stills (TMDB, referenced by URL, never hosted) and when a show's episode
/// refresh last failed, so the refresh loop backs off. Shows with a TMDB id are backdated to
/// stale, not cleared: the refresh loop serves never-loaded shows first, then fills stills.
struct AddEpisodeDetail: SQLMigration {
    let forward = [
        "ALTER TABLE show_episodes ADD COLUMN still_url text",
        "ALTER TABLE titles ADD COLUMN episodes_attempted_at timestamptz",
        """
        UPDATE titles SET episodes_hydrated_at = timestamptz '1970-01-01 00:00:00+00'
        WHERE type = 'show' AND episodes_hydrated_at IS NOT NULL AND tmdb IS NOT NULL
        """,
    ]
    let backward = [
        "ALTER TABLE titles DROP COLUMN episodes_attempted_at",
        "ALTER TABLE show_episodes DROP COLUMN still_url",
    ]
}

/// OUT-001 (minimal, for Stremio) · per-user agent tokens. Only the SHA-256 of the secret is
/// stored. `kind` names the outside caller so Settings can list Stremio links without guessing;
/// revoking keeps the row so journal entries can still name the token.
struct CreateAgentTokens: SQLMigration {
    let forward = [
        """
        CREATE TABLE agent_tokens (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
            kind text NOT NULL CHECK (kind IN ('stremio')),
            token_hash text NOT NULL UNIQUE,
            scopes text[] NOT NULL
                CHECK (scopes <@ ARRAY['library:read', 'library:write', 'scrobble:write']::text[]),
            created_at timestamptz NOT NULL DEFAULT now(),
            last_used_at timestamptz,
            expires_at timestamptz,
            revoked_at timestamptz
        )
        """,
        "CREATE INDEX agent_tokens_user ON agent_tokens (user_id) WHERE revoked_at IS NULL",
    ]
    let backward = [
        "DROP TABLE agent_tokens",
    ]
}

/// OUT-002 (minimal) · which agent token made a journaled write. Revoking a token keeps its
/// row, and deleting it only clears this column, so history stays readable.
struct AddActionAgentToken: SQLMigration {
    let forward = [
        "ALTER TABLE actions ADD COLUMN agent_token_id uuid REFERENCES agent_tokens(id) ON DELETE SET NULL",
    ]
    let backward = [
        "ALTER TABLE actions DROP COLUMN agent_token_id",
    ]
}

/// SCR-001 (service only) · one row per playback session from a player. A session is open
/// until `stop`; at most one is open per user, source and item. `title_id` is null when the
/// player's id resolved to nothing Aaru knows (an unmatched scrobble).
struct CreateWatchEvents: SQLMigration {
    let forward = [
        """
        CREATE TABLE watch_events (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            agent_token_id uuid REFERENCES agent_tokens(id) ON DELETE SET NULL,
            source text NOT NULL CHECK (source IN ('stremio')),
            external_ref text NOT NULL,
            title_id uuid REFERENCES titles(id) ON DELETE SET NULL,
            season integer,
            episode integer,
            state text NOT NULL CHECK (state IN ('playing', 'paused', 'stopped')),
            position_ms bigint NOT NULL DEFAULT 0,
            duration_ms bigint NOT NULL DEFAULT 0,
            started_at timestamptz NOT NULL,
            updated_at timestamptz NOT NULL,
            stopped_at timestamptz
        )
        """,
        """
        CREATE UNIQUE INDEX watch_events_open ON watch_events (user_id, source, external_ref)
        WHERE stopped_at IS NULL
        """,
        "CREATE INDEX watch_events_user ON watch_events (user_id, updated_at DESC)",
    ]
    let backward = [
        "DROP TABLE watch_events",
    ]
}

/// Multi-source imports (2026-10-20): an import may move a status forward, never past one the
/// user chose. The backfill marks items whose status a user edit changed and that still hold it.
struct AddStatusByHand: SQLMigration {
    let forward = [
        "ALTER TABLE library_items ADD COLUMN status_by_hand boolean NOT NULL DEFAULT false",
        """
        UPDATE library_items li SET status_by_hand = true
        WHERE EXISTS (
            SELECT 1 FROM actions a
            WHERE a.user_id = li.user_id AND li.id = ANY(a.item_ids) AND a.kind = 'update'
                AND a.actor = 'user' AND a.undone_at IS NULL
                AND a.inverse #>> '{setFields,_1,status}' IS DISTINCT FROM li.status
        )
        """,
        "CREATE INDEX anime_mappings_mal ON anime_mappings (mal) WHERE mal IS NOT NULL",
    ]
    let backward = [
        "DROP INDEX anime_mappings_mal",
        "ALTER TABLE library_items DROP COLUMN status_by_hand",
    ]
}

/// Web push (2026-10-20): one row per browser subscription. Deleting the user deletes them.
struct CreateWebPush: SQLMigration {
    let forward = [
        """
        CREATE TABLE web_push_subscriptions (
            endpoint text PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            p256dh text NOT NULL,
            auth text NOT NULL,
            vapid_key_id text NOT NULL,
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """,
        "CREATE INDEX web_push_subscriptions_user ON web_push_subscriptions (user_id)",
    ]
    let backward = [
        "DROP TABLE web_push_subscriptions",
    ]
}

/// Stremio history import (IMP-016): a link code waiting for the user's approval on stremio.com.
/// Only the code and its owner are kept, never Stremio's session key.
struct CreateStremioLinkRequests: SQLMigration {
    let forward = [
        """
        CREATE TABLE stremio_link_requests (
            code text PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            expires_at timestamptz NOT NULL
        )
        """,
    ]
    let backward = ["DROP TABLE stremio_link_requests"]
}

/// IMP-017 · how far the worker has matched a job's rows, so an import shows progress instead of
/// a bare "Waiting". Written every few rows while matching, reset when a job is retried.
struct AddImportProgress: SQLMigration {
    let forward = ["ALTER TABLE import_jobs ADD COLUMN rows_matched integer NOT NULL DEFAULT 0"]
    let backward = ["ALTER TABLE import_jobs DROP COLUMN rows_matched"]
}
