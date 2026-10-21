/// MUS-003 · concerts. An album's artists by MusicBrainz id (filled from MusicBrainz once per
/// album), each artist's concert-provider id when one carries the same MusicBrainz id, and the
/// user's "Concerts near" city, rounded to two decimals (about a kilometre).
struct AddConcerts: SQLMigration {
    let forward = [
        "ALTER TABLE titles ADD COLUMN artists_checked_at timestamptz",
        """
        CREATE TABLE music_artists (
            musicbrainz text PRIMARY KEY,
            name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 500),
            performer_id text,
            matched_at timestamptz
        )
        """,
        """
        CREATE TABLE album_artists (
            title_id uuid NOT NULL REFERENCES titles(id) ON DELETE CASCADE,
            artist text NOT NULL REFERENCES music_artists(musicbrainz) ON DELETE CASCADE,
            position integer NOT NULL CHECK (position >= 0),
            PRIMARY KEY (title_id, artist)
        )
        """,
        "CREATE INDEX album_artists_artist ON album_artists (artist)",
        """
        CREATE TABLE concert_places (
            user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 200),
            region text CHECK (char_length(region) BETWEEN 1 AND 200),
            country text CHECK (char_length(country) BETWEEN 1 AND 200),
            country_code text CHECK (char_length(country_code) = 2),
            latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
            longitude double precision NOT NULL CHECK (longitude BETWEEN -180 AND 180),
            updated_at timestamptz NOT NULL
        )
        """,
    ]
    let backward = [
        "DROP TABLE concert_places",
        "DROP TABLE album_artists",
        "DROP TABLE music_artists",
        "ALTER TABLE titles DROP COLUMN artists_checked_at",
    ]
}
