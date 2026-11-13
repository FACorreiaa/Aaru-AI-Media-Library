-- A book may be far older than film: Pride and Prejudice is 1813, and the old floor of 1870
-- refused it. The per-kind rule lives in core.ValidYear (books from 1000, everything else from
-- 1870); the database keeps only the widest bound.

-- +goose Up
ALTER TABLE titles DROP CONSTRAINT titles_year_check;
ALTER TABLE titles ADD CONSTRAINT titles_year_check CHECK (year >= 1000 AND year <= 2200);

-- +goose Down
ALTER TABLE titles DROP CONSTRAINT titles_year_check;
ALTER TABLE titles ADD CONSTRAINT titles_year_check CHECK (year >= 1870 AND year <= 2200) NOT VALID;
