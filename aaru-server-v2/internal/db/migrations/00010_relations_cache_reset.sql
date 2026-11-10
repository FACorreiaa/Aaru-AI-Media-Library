-- Relation graph (GRAPH-001): clear cached answers that the 2026-11-10 fixes make wrong. Wikidata's
-- answers now carry the title's own ids and a series' parts, and "nothing related" is believed for a
-- day, not a month. `catalog_relations` is a cache of catalog data: every row is fetched again when a
-- graph needs it.

-- +goose Up
DELETE FROM catalog_relations
WHERE source = 'wikidata' OR jsonb_array_length(relations -> 'edges') = 0;

-- +goose Down
SELECT 1;
