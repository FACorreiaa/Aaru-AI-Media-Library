-- Book capture (BOOK-001): one capture may be several pictures, and may ask for books only.
--
-- capture_images holds the pictures after the first, which stays in capture_inputs.image, so an
-- input already waiting when this runs still reads. They go when the input goes: read, or swept
-- after an hour.

-- +goose Up
ALTER TABLE capture_inputs ADD COLUMN only_type text;

CREATE TABLE capture_images (
    job_id uuid NOT NULL REFERENCES capture_inputs (job_id) ON DELETE CASCADE,
    position integer NOT NULL,
    image bytea NOT NULL,
    media_type text NOT NULL,
    PRIMARY KEY (job_id, position)
);

-- +goose Down
DROP TABLE capture_images;
ALTER TABLE capture_inputs DROP COLUMN only_type;
