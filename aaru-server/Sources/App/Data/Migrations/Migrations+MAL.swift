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

/// LIB-007 · on hold, Aaru's fifth status (owner, 2026-10-25). Until now every import read MAL's
/// on hold as in progress, so it filled Watching. The backfill puts back on hold the items in
/// progress that nobody set by hand and whose MAL entries, as Aaru last read or wrote them, have
/// one on hold and none watching. A TMDB show stands for the MAL entries its anime mapping names.
struct AddOnHold: SQLMigration {
    static let backfill = """
    WITH entries AS (
        SELECT li.id, s.status
        FROM library_items li
        JOIN titles t ON t.id = li.title_id
        JOIN mal_entry_states s ON s.user_id = li.user_id AND s.removed_at IS NULL
            AND (s.mal_id = t.mal
                 OR (t.type = 'show' AND s.mal_id IN (SELECT m.mal FROM anime_mappings m WHERE m.tmdb = t.tmdb)))
        WHERE li.status = 'in_progress' AND NOT li.status_by_hand
    )
    UPDATE library_items SET status = 'on_hold', updated_at = now()
    WHERE id IN (
        SELECT id FROM entries GROUP BY id
        HAVING bool_or(status = 'on_hold') AND NOT bool_or(status = 'watching')
    )
    """

    let forward = [
        """
        ALTER TABLE library_items DROP CONSTRAINT library_items_status_check,
            ADD CONSTRAINT library_items_status_check
                CHECK (status IN ('wishlist', 'in_progress', 'on_hold', 'finished', 'dropped'))
        """,
        Self.backfill,
    ]
    let backward = [
        "UPDATE library_items SET status = 'in_progress', updated_at = now() WHERE status = 'on_hold'",
        """
        ALTER TABLE library_items DROP CONSTRAINT library_items_status_check,
            ADD CONSTRAINT library_items_status_check
                CHECK (status IN ('wishlist', 'in_progress', 'finished', 'dropped'))
        """,
    ]
}
