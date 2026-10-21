/// MUS-001 · albums as a fifth kind: the `album` type, the MusicBrainz release-group id
/// (globally unique, like the anime ids), the artist credit, and a tracklist filled the first
/// time an album's page opens.
struct AddMusic: SQLMigration {
    let forward = [
        "ALTER TABLE titles DROP CONSTRAINT titles_type_check",
        "ALTER TABLE titles ADD CONSTRAINT titles_type_check CHECK (type IN ('movie', 'show', 'book', 'album'))",
        "ALTER TABLE titles ADD COLUMN musicbrainz text",
        "CREATE UNIQUE INDEX titles_musicbrainz_key ON titles (musicbrainz) WHERE musicbrainz IS NOT NULL",
        "ALTER TABLE titles ADD COLUMN byline text",
        "ALTER TABLE titles ADD COLUMN tracks_hydrated_at timestamptz",
        """
        CREATE TABLE album_tracks (
            title_id uuid NOT NULL REFERENCES titles(id) ON DELETE CASCADE,
            disc integer NOT NULL CHECK (disc >= 1),
            position integer NOT NULL CHECK (position >= 1),
            name text NOT NULL,
            length_ms integer CHECK (length_ms >= 0),
            PRIMARY KEY (title_id, disc, position)
        )
        """,
    ]
    let backward = [
        "DROP TABLE album_tracks",
        "ALTER TABLE titles DROP COLUMN tracks_hydrated_at",
        "ALTER TABLE titles DROP COLUMN byline",
        "DROP INDEX titles_musicbrainz_key",
        "ALTER TABLE titles DROP COLUMN musicbrainz",
        "DELETE FROM titles WHERE type = 'album'",
        "ALTER TABLE titles DROP CONSTRAINT titles_type_check",
        "ALTER TABLE titles ADD CONSTRAINT titles_type_check CHECK (type IN ('movie', 'show', 'book'))",
    ]
}
