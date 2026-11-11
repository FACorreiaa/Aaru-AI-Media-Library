-- Title tree (GRAPH-005): who made a title, and what else that person made, as one provider
-- answered. Catalog data from TMDB, AniList, Open Library and MusicBrainz, keyed by the source and
-- the provider's own id (`title:…` for a title's people, `person:…` for a person's works); no user.
-- A row past its window is fetched again when a tree needs it; a failed fetch serves the old row.

-- +goose Up
CREATE TABLE catalog_credits (
    source text NOT NULL,
    key text NOT NULL,
    payload jsonb NOT NULL,
    fetched_at timestamptz NOT NULL,
    PRIMARY KEY (source, key)
);

-- +goose Down
DROP TABLE catalog_credits;
