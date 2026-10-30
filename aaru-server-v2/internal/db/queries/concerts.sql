-- PostgresConcertStore.swift: the "Concerts near" city, album artists and their Ticketmaster matches (MUS-003).

-- name: ConcertPlace :one
SELECT name, region, country, country_code, latitude, longitude FROM concert_places
WHERE user_id = $1;

-- name: SaveConcertPlace :exec
INSERT INTO concert_places (user_id, name, region, country, country_code, latitude, longitude, updated_at)
VALUES (sqlc.arg(user_id), sqlc.arg(name), sqlc.narg(region), sqlc.narg(country), sqlc.narg(country_code),
    sqlc.arg(latitude), sqlc.arg(longitude), sqlc.arg(updated_at))
ON CONFLICT (user_id) DO UPDATE SET name = EXCLUDED.name, region = EXCLUDED.region,
    country = EXCLUDED.country, country_code = EXCLUDED.country_code, latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude, updated_at = EXCLUDED.updated_at;

-- name: DeleteConcertPlace :exec
DELETE FROM concert_places WHERE user_id = $1;

-- name: AlbumsMissingArtists :many
SELECT t.id, t.musicbrainz::text AS musicbrainz FROM titles t
WHERE t.type = 'album' AND t.musicbrainz IS NOT NULL AND t.artists_checked_at IS NULL
  AND EXISTS (SELECT 1 FROM library_items li WHERE li.title_id = t.id)
ORDER BY t.id
LIMIT $1;

-- name: UpsertMusicArtist :exec
INSERT INTO music_artists (musicbrainz, name)
VALUES ($1, $2)
ON CONFLICT (musicbrainz) DO UPDATE SET name = EXCLUDED.name;

-- name: UpsertAlbumArtist :exec
INSERT INTO album_artists (title_id, artist, position)
VALUES ($1, $2, $3)
ON CONFLICT (title_id, artist) DO UPDATE SET position = EXCLUDED.position;

-- name: MarkAlbumArtistsChecked :exec
UPDATE titles SET artists_checked_at = $2 WHERE id = $1;

-- Never-asked artists first, then the longest-unchecked.
-- name: ArtistsToMatch :many
SELECT a.musicbrainz, a.name FROM music_artists a
WHERE (a.matched_at IS NULL OR a.matched_at < sqlc.arg(checked_before))
  AND EXISTS (
    SELECT 1 FROM album_artists aa JOIN library_items li ON li.title_id = aa.title_id
    WHERE aa.artist = a.musicbrainz
  )
ORDER BY a.matched_at NULLS FIRST, a.musicbrainz
LIMIT sqlc.arg(row_limit);

-- name: SaveArtistMatch :exec
UPDATE music_artists SET performer_id = sqlc.narg(performer_id), matched_at = sqlc.arg(matched_at)
WHERE musicbrainz = sqlc.arg(musicbrainz);

-- name: LibraryArtists :many
SELECT a.musicbrainz, a.name, a.performer_id, a.matched_at FROM music_artists a
JOIN album_artists aa ON aa.artist = a.musicbrainz
JOIN library_items li ON li.title_id = aa.title_id
WHERE li.user_id = $1 AND li.status <> 'dropped'
GROUP BY a.musicbrainz, a.name, a.performer_id, a.matched_at
ORDER BY count(*) DESC, a.name;
