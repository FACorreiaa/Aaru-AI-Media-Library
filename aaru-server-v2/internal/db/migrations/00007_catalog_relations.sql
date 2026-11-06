-- Relation graph (GRAPH-001): one relation source's answer for one title, cached. Catalog data from
-- AniList, TMDB collections and Wikidata, keyed by the source and the id it was asked with; no user.
-- A row past its window is fetched again when a graph needs it; a failed fetch serves the old row.

-- +goose Up
CREATE TABLE catalog_relations (
    source text NOT NULL,
    node_key text NOT NULL,
    relations jsonb NOT NULL,
    fetched_at timestamptz NOT NULL,
    PRIMARY KEY (source, node_key)
);

-- +goose Down
DROP TABLE catalog_relations;
