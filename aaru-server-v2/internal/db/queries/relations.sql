-- name: CatalogRelations :one
-- One source's cached answer for one title (GRAPH-001).
SELECT relations, fetched_at FROM catalog_relations WHERE source = @source AND node_key = @node_key;

-- name: PutCatalogRelations :exec
INSERT INTO catalog_relations (source, node_key, relations, fetched_at)
VALUES (@source, @node_key, @relations, @fetched_at)
ON CONFLICT (source, node_key) DO UPDATE SET relations = EXCLUDED.relations, fetched_at = EXCLUDED.fetched_at;

-- name: LibraryEntriesMatchingCatalog :many
-- The user's items among titles carrying these provider ids, with their status: the relation
-- graph's marks (GRAPH-001).
SELECT li.id, li.status, t.type, t.tmdb, t.anilist, t.open_library, t.musicbrainz FROM library_items li
JOIN titles t ON t.id = li.title_id
WHERE li.user_id = @user_id
  AND (t.tmdb = ANY(@tmdb::text[]) OR t.anilist = ANY(@anilist::text[])
       OR t.open_library = ANY(@open_library::text[])
       OR t.musicbrainz = ANY(@musicbrainz::text[]));
