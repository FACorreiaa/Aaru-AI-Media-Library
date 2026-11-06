-- Roadmap lists (GRAPH-003): a list the owl planned in steps keeps them here, beside its membership,
-- which stays in list_items. One row per list: its steps, each with a heading, a note, the titles
-- Aaru could not find (as text), and each member's note, optional flag and side-by-side pair. It goes
-- with the list; a member removed by hand simply stops being shown in its step.

-- +goose Up
CREATE TABLE list_roadmaps (
    list_id uuid PRIMARY KEY REFERENCES lists(id) ON DELETE CASCADE,
    roadmap jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- +goose Down
DROP TABLE list_roadmaps;
