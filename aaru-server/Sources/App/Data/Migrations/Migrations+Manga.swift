/// MNG-001 · manga as a sixth kind: the `manga` type, its chapter and volume counts, and a reading
/// position on the library item. MyAnimeList numbers anime and manga separately, so the global
/// `mal` index splits in two: anime 1 and manga 1 are different works. AniList shares one id
/// space between them, so `anilist` stays global.
struct AddManga: SQLMigration {
    let forward = [
        "ALTER TABLE titles DROP CONSTRAINT titles_type_check",
        """
        ALTER TABLE titles ADD CONSTRAINT titles_type_check
            CHECK (type IN ('movie', 'show', 'book', 'album', 'manga'))
        """,
        "ALTER TABLE titles ADD COLUMN chapter_count integer CHECK (chapter_count > 0)",
        "ALTER TABLE titles ADD COLUMN volume_count integer CHECK (volume_count > 0)",
        "DROP INDEX titles_mal_key",
        "CREATE UNIQUE INDEX titles_mal_key ON titles (mal) WHERE mal IS NOT NULL AND type <> 'manga'",
        "CREATE UNIQUE INDEX titles_manga_mal_key ON titles (mal) WHERE mal IS NOT NULL AND type = 'manga'",
        "ALTER TABLE library_items ADD COLUMN manga_chapter integer CHECK (manga_chapter >= 0)",
        "ALTER TABLE library_items ADD COLUMN manga_volume integer CHECK (manga_volume >= 0)",
    ]
    let backward = [
        "ALTER TABLE library_items DROP COLUMN manga_volume",
        "ALTER TABLE library_items DROP COLUMN manga_chapter",
        "DELETE FROM titles WHERE type = 'manga'",
        "DROP INDEX titles_manga_mal_key",
        "DROP INDEX titles_mal_key",
        "CREATE UNIQUE INDEX titles_mal_key ON titles (mal) WHERE mal IS NOT NULL",
        "ALTER TABLE titles DROP COLUMN volume_count",
        "ALTER TABLE titles DROP COLUMN chapter_count",
        "ALTER TABLE titles DROP CONSTRAINT titles_type_check",
        "ALTER TABLE titles ADD CONSTRAINT titles_type_check CHECK (type IN ('movie', 'show', 'book', 'album'))",
    ]
}
