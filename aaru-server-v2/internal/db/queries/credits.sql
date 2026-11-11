-- name: CatalogCredits :one
-- One source's cached answer for a title's people or a person's works (GRAPH-005).
SELECT payload, fetched_at FROM catalog_credits WHERE source = @source AND key = @key;

-- name: PutCatalogCredits :exec
INSERT INTO catalog_credits (source, key, payload, fetched_at)
VALUES (@source, @key, @payload, @fetched_at)
ON CONFLICT (source, key) DO UPDATE SET payload = EXCLUDED.payload, fetched_at = EXCLUDED.fetched_at;
