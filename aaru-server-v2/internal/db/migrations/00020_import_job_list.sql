-- The list an approved import's titles joined (ASK-012), kept by id. It was found by name, so a
-- later list of the same name could pass for it: an import that made no list then pointed at
-- another import's list, and a title matched by hand joined it. No foreign key: Undo deletes the
-- list and Redo brings it back with the same id, and the read checks the list is still there.
-- Jobs approved before this keep the list their name finds today, as the read used to.

-- +goose Up
ALTER TABLE import_jobs ADD COLUMN list_id uuid;

UPDATE import_jobs j SET list_id = (
    SELECT l.id
    FROM import_rows r
    JOIN lists l ON l.user_id = j.user_id AND lower(l.name) = lower(r."row" -> 'lists' ->> 0)
    WHERE r.job_id = j.id AND jsonb_typeof(r."row" -> 'lists') = 'array'
    ORDER BY r.idx, l.created_at
    LIMIT 1
)
WHERE j.state IN ('succeeded', 'partial');

-- +goose Down
ALTER TABLE import_jobs DROP COLUMN IF EXISTS list_id;
