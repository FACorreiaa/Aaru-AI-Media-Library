/// CAT-018: the provider's genres, stored at hydration (TMDB and AniList; books have none).
/// `genres_attempted_at` paces the backfill so a title the provider gives no genres is not
/// asked again every pass.
struct AddTitleGenres: SQLMigration {
    let forward = [
        "ALTER TABLE titles ADD COLUMN genres text[] NOT NULL DEFAULT '{}'",
        "ALTER TABLE titles ADD COLUMN genres_attempted_at timestamptz",
    ]
    let backward = [
        "ALTER TABLE titles DROP COLUMN genres_attempted_at",
        "ALTER TABLE titles DROP COLUMN genres",
    ]
}
