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

/// MUS-005 · the listening log: one row per play of a track, append-only and never library
/// truth. Scrobblers reach it with a `music` token over ListenBrainz's protocol. `track_key` is
/// the normalized artist and track, so the same play sent by two scrobblers is kept once.
struct AddListens: SQLMigration {
    let forward = [
        "ALTER TABLE agent_tokens DROP CONSTRAINT agent_tokens_kind_check",
        """
        ALTER TABLE agent_tokens ADD CONSTRAINT agent_tokens_kind_check
            CHECK (kind IN ('stremio', 'claude_code', 'codex', 'hermes', 'gemini', 'other', 'claude', 'browser',
                            'music'))
        """,
        """
        CREATE TABLE listens (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            listened_at timestamptz NOT NULL,
            artist text NOT NULL CHECK (char_length(artist) BETWEEN 1 AND 500),
            track text NOT NULL CHECK (char_length(track) BETWEEN 1 AND 500),
            album text CHECK (char_length(album) BETWEEN 1 AND 500),
            track_key text NOT NULL,
            duration_ms integer CHECK (duration_ms > 0),
            isrc text,
            recording_mbid text,
            release_mbid text,
            release_group_mbid text,
            artist_mbid text,
            spotify_id text,
            origin_url text,
            client text,
            music_service text,
            source text NOT NULL CHECK (source IN ('live')),
            agent_token_id uuid REFERENCES agent_tokens(id) ON DELETE SET NULL,
            created_at timestamptz NOT NULL DEFAULT now(),
            UNIQUE (user_id, track_key, listened_at)
        )
        """,
        "CREATE INDEX listens_user_time ON listens (user_id, listened_at DESC)",
    ]
    let backward = [
        "DROP TABLE listens",
        "DELETE FROM agent_tokens WHERE kind = 'music'",
        "ALTER TABLE agent_tokens DROP CONSTRAINT agent_tokens_kind_check",
        """
        ALTER TABLE agent_tokens ADD CONSTRAINT agent_tokens_kind_check
            CHECK (kind IN ('stremio', 'claude_code', 'codex', 'hermes', 'gemini', 'other', 'claude', 'browser'))
        """,
    ]
}
