-- Catalog layer: titles, episodes, album tracks, anime mappings (PostgresCatalogStores*.swift).
-- `type` scopes tmdb and trakt (their unique indexes are per type).

-- name: InsertTitle :exec
INSERT INTO titles (
    id, type, title, original_title, year, synopsis, poster_url, backdrop_url, network, byline,
    page_count, chapter_count, volume_count,
    tmdb, imdb, trakt, tvdb, isbn, open_library, anilist, mal, anidb, musicbrainz,
    is_anime, status, runtime_minutes, genres
) VALUES (
    @id, @type, @title, @original_title, @year, @synopsis, @poster_url, @backdrop_url, @network, @byline,
    @page_count, @chapter_count, @volume_count,
    @tmdb, @imdb, @trakt, @tvdb, @isbn, @open_library, @anilist, @mal, @anidb, @musicbrainz,
    @is_anime, @status, @runtime_minutes, @genres::text[]
);

-- name: TitleByID :one
SELECT * FROM titles WHERE id = $1;

-- name: FindTitle :one
-- The oldest title of this type holding any of these ids. A null id matches nothing.
SELECT * FROM titles
WHERE type = @type
  AND (tmdb = sqlc.narg(tmdb) OR imdb = sqlc.narg(imdb) OR trakt = sqlc.narg(trakt) OR tvdb = sqlc.narg(tvdb)
       OR isbn = sqlc.narg(isbn) OR open_library = sqlc.narg(open_library) OR anilist = sqlc.narg(anilist)
       OR mal = sqlc.narg(mal) OR anidb = sqlc.narg(anidb) OR musicbrainz = sqlc.narg(musicbrainz))
ORDER BY created_at
LIMIT 1;

-- name: FillTitleIDs :exec
-- Fill-empty-only: each given id lands only where the column is still null.
UPDATE titles SET
    tmdb = coalesce(tmdb, sqlc.narg(tmdb)), imdb = coalesce(imdb, sqlc.narg(imdb)),
    trakt = coalesce(trakt, sqlc.narg(trakt)), tvdb = coalesce(tvdb, sqlc.narg(tvdb)),
    isbn = coalesce(isbn, sqlc.narg(isbn)), open_library = coalesce(open_library, sqlc.narg(open_library)),
    anilist = coalesce(anilist, sqlc.narg(anilist)), mal = coalesce(mal, sqlc.narg(mal)),
    anidb = coalesce(anidb, sqlc.narg(anidb)), musicbrainz = coalesce(musicbrainz, sqlc.narg(musicbrainz))
WHERE id = @id
  AND ((sqlc.narg(tmdb)::text IS NOT NULL AND tmdb IS NULL)
       OR (sqlc.narg(imdb)::text IS NOT NULL AND imdb IS NULL)
       OR (sqlc.narg(trakt)::text IS NOT NULL AND trakt IS NULL)
       OR (sqlc.narg(tvdb)::text IS NOT NULL AND tvdb IS NULL)
       OR (sqlc.narg(isbn)::text IS NOT NULL AND isbn IS NULL)
       OR (sqlc.narg(open_library)::text IS NOT NULL AND open_library IS NULL)
       OR (sqlc.narg(anilist)::text IS NOT NULL AND anilist IS NULL)
       OR (sqlc.narg(mal)::text IS NOT NULL AND mal IS NULL)
       OR (sqlc.narg(anidb)::text IS NOT NULL AND anidb IS NULL)
       OR (sqlc.narg(musicbrainz)::text IS NOT NULL AND musicbrainz IS NULL));

-- name: TitlesByIDs :many
SELECT * FROM titles WHERE id = ANY(@ids::uuid[]);

-- name: TitleAiring :many
-- Status and first unaired episode of each show among these ids (LST-003).
SELECT t.id, t.status, next.season, next.episode, next.name, next.airs_at, next.airs_at_exact
FROM titles t
LEFT JOIN LATERAL (
    SELECT se.season, se.episode, se.name, se.airs_at, se.airs_at_exact FROM show_episodes se
    WHERE se.title_id = t.id AND se.season > 0 AND se.airs_at > @now
    ORDER BY se.airs_at, se.season, se.episode LIMIT 1
) next ON true
WHERE t.type = 'show' AND t.id = ANY(@ids::uuid[]);

-- name: StaleTrackedShows :many
SELECT t.id FROM titles t
WHERE t.type = 'show'
  AND (EXISTS (SELECT 1 FROM library_items li
               WHERE li.title_id = t.id AND li.status IN ('wishlist', 'in_progress'))
       OR EXISTS (SELECT 1 FROM list_items lst WHERE lst.title_id = t.id))
  AND (t.episodes_attempted_at IS NULL OR t.episodes_attempted_at < @retry_after)
  AND (t.episodes_hydrated_at IS NULL
       OR t.episodes_hydrated_at < @dormant_stale
       OR (t.episodes_hydrated_at < @airing_stale
           AND EXISTS (SELECT 1 FROM show_episodes e
                       WHERE e.title_id = t.id
                         AND e.airs_at BETWEEN @window_start AND @window_end)))
ORDER BY t.episodes_hydrated_at NULLS FIRST, t.id
LIMIT @lim;

-- name: MarkEpisodesAttempted :exec
UPDATE titles SET episodes_attempted_at = @at WHERE id = @id;

-- name: ShowEpisodes :many
SELECT season, episode, name, airs_at, airs_at_exact, runtime_minutes, tmdb_episode_id, overview, still_url
FROM show_episodes WHERE title_id = $1 ORDER BY season, episode;

-- name: StampEpisodesHydrated :exec
-- A provider that drops its art does not erase ours.
UPDATE titles SET backdrop_url = coalesce(sqlc.narg(backdrop_url), backdrop_url),
    network = coalesce(sqlc.narg(network), network), episodes_hydrated_at = @hydrated_at,
    status = sqlc.narg(status), updated_at = @hydrated_at
WHERE id = @id;

-- name: DeleteAlbumTracks :exec
DELETE FROM album_tracks WHERE title_id = $1;

-- name: StampTracksHydrated :exec
UPDATE titles SET tracks_hydrated_at = @hydrated_at, updated_at = @hydrated_at WHERE id = @id;

-- name: AlbumTracks :many
SELECT disc, position, name, length_ms FROM album_tracks WHERE title_id = $1 ORDER BY disc, position;

-- name: TitlesMissingGenres :many
-- CAT-018 backfill: films, shows and anime someone keeps, with no genres, not tried since retry_after.
SELECT t.* FROM titles t
WHERE t.type NOT IN ('book', 'album') AND t.genres = '{}'
  AND (t.genres_attempted_at IS NULL OR t.genres_attempted_at < @retry_after)
  AND (EXISTS (SELECT 1 FROM library_items li WHERE li.title_id = t.id)
       OR EXISTS (SELECT 1 FROM list_items lst WHERE lst.title_id = t.id))
ORDER BY t.genres_attempted_at NULLS FIRST, t.created_at, t.id
LIMIT @lim;

-- name: FillGenres :exec
UPDATE titles
SET genres = CASE WHEN genres = '{}' THEN @genres::text[] ELSE genres END,
    genres_attempted_at = @attempted_at
WHERE id = @id;

-- name: TitleGenres :one
SELECT genres FROM titles WHERE id = $1;

-- name: BooksMissingPageCount :many
-- APP-017 backfill: shelved books with no page count, in-progress first.
SELECT t.id FROM titles t
WHERE t.type = 'book' AND t.page_count IS NULL
  AND (t.page_count_attempted_at IS NULL OR t.page_count_attempted_at < @retry_after)
  AND EXISTS (SELECT 1 FROM library_items li WHERE li.title_id = t.id)
ORDER BY EXISTS (
        SELECT 1 FROM library_items li WHERE li.title_id = t.id AND li.status = 'in_progress'
    ) DESC,
    t.page_count_attempted_at NULLS FIRST, t.created_at, t.id
LIMIT @lim;

-- name: FillPageCount :exec
UPDATE titles
SET page_count = coalesce(page_count, sqlc.narg(page_count)), page_count_attempted_at = @attempted_at
WHERE id = @id;

-- name: AnimeMappingByAniList :one
SELECT * FROM anime_mappings WHERE anilist = $1 ORDER BY anilist LIMIT 1;

-- name: AnimeMappingByMAL :one
SELECT * FROM anime_mappings WHERE mal = $1 ORDER BY anilist LIMIT 1;

-- name: AnimeMappingsByAniList :many
SELECT * FROM anime_mappings WHERE anilist = ANY(@ids::text[]);

-- name: AnimeMappingsByMAL :many
-- The first mapping per MAL id, as AnimeMappingByMAL picks it.
SELECT DISTINCT ON (mal) * FROM anime_mappings WHERE mal = ANY(@ids::text[]) ORDER BY mal, anilist;

-- name: AnimeMappingsByTMDB :many
SELECT * FROM anime_mappings WHERE tmdb = ANY(@ids::text[]);

-- name: UpsertAnimeMapping :exec
INSERT INTO anime_mappings (anilist, mal, anidb, tvdb, tmdb, tmdb_season)
VALUES (@anilist, sqlc.narg(mal), sqlc.narg(anidb), sqlc.narg(tvdb), sqlc.narg(tmdb), sqlc.narg(tmdb_season))
ON CONFLICT (anilist) DO UPDATE SET
    mal = EXCLUDED.mal, anidb = EXCLUDED.anidb, tvdb = EXCLUDED.tvdb,
    tmdb = EXCLUDED.tmdb, tmdb_season = EXCLUDED.tmdb_season;

-- name: LibraryItemsMatchingCatalog :many
-- The user's items among titles carrying these provider ids: Discover's "in library" mark.
SELECT li.id, t.type, t.tmdb, t.anilist, t.open_library, t.musicbrainz FROM library_items li
JOIN titles t ON t.id = li.title_id
WHERE li.user_id = @user_id
  AND (t.tmdb = ANY(@tmdb::text[]) OR t.anilist = ANY(@anilist::text[])
       OR t.open_library = ANY(@open_library::text[])
       OR t.musicbrainz = ANY(@musicbrainz::text[]));

-- name: LibraryItemIDForTitle :one
SELECT id FROM library_items WHERE user_id = @user_id AND title_id = @title_id;
