import FluentSQL

/// SHR-002: share links. One row per link, pointing at exactly one title, sport event or
/// concert. A deleted sender leaves the link working with no name and no note.
struct CreateShares: SQLMigration {
    let forward = [
        """
        CREATE TABLE shares (
            code text PRIMARY KEY,
            sender_id uuid REFERENCES users(id) ON DELETE SET NULL,
            kind text NOT NULL CHECK (kind IN ('title', 'sport_event', 'concert')),
            title_id uuid REFERENCES titles(id) ON DELETE RESTRICT,
            sport_event_id text,
            concert_id text,
            note text CHECK (note IS NULL OR char_length(note) <= 140),
            created_at timestamptz NOT NULL,
            CHECK ((kind = 'title') = (title_id IS NOT NULL)
               AND (kind = 'sport_event') = (sport_event_id IS NOT NULL)
               AND (kind = 'concert') = (concert_id IS NOT NULL))
        )
        """,
        "CREATE INDEX shares_sender ON shares (sender_id, created_at DESC)",
        "CREATE INDEX shares_title ON shares (title_id)",
    ]
    let backward = ["DROP TABLE shares"]
}
