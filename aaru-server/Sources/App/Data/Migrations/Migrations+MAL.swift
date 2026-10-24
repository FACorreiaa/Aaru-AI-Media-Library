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
