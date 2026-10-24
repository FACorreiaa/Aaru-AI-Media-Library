import FluentKit
import FluentSQL

/// SCR-005 · MyAnimeList connect and push: one connection per user (tokens encrypted with
/// MAL_TOKEN_KEY) with the time up to which library writes were pushed, PKCE sign-ins in flight,
/// and what Aaru and MAL last agreed on per MAL entry.
struct CreateMALConnections: SQLMigration {
    let forward = [
        """
        CREATE TABLE mal_connections (
            user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            access_token text NOT NULL,
            refresh_token text NOT NULL,
            expires_at timestamptz NOT NULL,
            username text,
            connected_at timestamptz NOT NULL DEFAULT now(),
            push_cursor timestamptz NOT NULL,
            revoked_at timestamptz
        )
        """,
        """
        CREATE TABLE mal_auth_requests (
            state_hash text PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            code_verifier text NOT NULL,
            return_to text NOT NULL,
            expires_at timestamptz NOT NULL
        )
        """,
        """
        CREATE TABLE mal_entry_states (
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            mal_id text NOT NULL,
            status text NOT NULL
                CHECK (status IN ('watching', 'completed', 'on_hold', 'dropped', 'plan_to_watch')),
            episodes integer NOT NULL CHECK (episodes >= 0),
            score integer NOT NULL CHECK (score BETWEEN 0 AND 10),
            updated_at timestamptz NOT NULL DEFAULT now(),
            PRIMARY KEY (user_id, mal_id)
        )
        """,
        // The anime mapping is read by TMDB id to split a show back into MAL entries.
        "CREATE INDEX IF NOT EXISTS anime_mappings_tmdb ON anime_mappings (tmdb) WHERE tmdb IS NOT NULL",
    ]
    let backward = [
        "DROP INDEX IF EXISTS anime_mappings_tmdb",
        "DROP TABLE mal_entry_states",
        "DROP TABLE mal_auth_requests",
        "DROP TABLE mal_connections",
    ]
}

/// SCR-010 · reading MyAnimeList back: how far each connection has read (MAL's own
/// `list_updated_at`), when it last read and when a client last asked, when it last read the
/// whole list; per entry, the title to show and when it went missing on MAL.
struct AddMALPull: SQLMigration {
    let forward = [
        """
        ALTER TABLE mal_connections
            ADD COLUMN pull_cursor timestamptz,
            ADD COLUMN pulled_at timestamptz,
            ADD COLUMN pull_requested_at timestamptz,
            ADD COLUMN full_read_at timestamptz
        """,
        "ALTER TABLE mal_entry_states ADD COLUMN title text, ADD COLUMN removed_at timestamptz",
    ]
    let backward = [
        "ALTER TABLE mal_entry_states DROP COLUMN removed_at, DROP COLUMN title",
        """
        ALTER TABLE mal_connections DROP COLUMN full_read_at, DROP COLUMN pull_requested_at,
            DROP COLUMN pulled_at, DROP COLUMN pull_cursor
        """,
    ]
}
