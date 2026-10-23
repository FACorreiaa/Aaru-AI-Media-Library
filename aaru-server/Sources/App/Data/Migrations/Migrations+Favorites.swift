import FluentSQL

/// FAV-001: a user's ordered top 10 per kind. A title in use as a favorite is never deleted.
struct CreateFavorites: SQLMigration {
    let forward = [
        """
        CREATE TABLE favorites (
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            kind text NOT NULL CHECK (kind IN ('film', 'show', 'anime', 'manga', 'book', 'album')),
            position integer NOT NULL CHECK (position BETWEEN 0 AND 9),
            title_id uuid NOT NULL REFERENCES titles(id) ON DELETE RESTRICT,
            created_at timestamptz NOT NULL DEFAULT now(),
            PRIMARY KEY (user_id, kind, position),
            UNIQUE (user_id, kind, title_id)
        )
        """,
        "CREATE INDEX favorites_title ON favorites (title_id)",
    ]
    let backward = ["DROP TABLE favorites"]
}
