-- Sessions that mark everyone who joined, and reading sessions (ROOM-005). A member's watch_ready
-- row now says whether the host ending the session marks the title for them (auto_mark, on unless
-- they switch it off), when it was marked, and the journal action that did it, so the ended
-- screen can offer Undo. A session can aim at a manga chapter and volume or a book page, beside
-- a show's season and episode.

-- +goose Up
ALTER TABLE watch_ready
    ADD COLUMN auto_mark boolean NOT NULL DEFAULT true,
    ADD COLUMN marked_at timestamp with time zone,
    ADD COLUMN action_id uuid;

ALTER TABLE watch_sessions
    ADD COLUMN chapter integer,
    ADD COLUMN volume integer,
    ADD COLUMN page integer,
    ADD CONSTRAINT watch_sessions_chapter_check CHECK (chapter >= 0),
    ADD CONSTRAINT watch_sessions_volume_check CHECK (volume >= 0),
    ADD CONSTRAINT watch_sessions_page_check CHECK (page >= 0);

-- +goose Down
ALTER TABLE watch_sessions
    DROP CONSTRAINT watch_sessions_page_check,
    DROP CONSTRAINT watch_sessions_volume_check,
    DROP CONSTRAINT watch_sessions_chapter_check,
    DROP COLUMN page,
    DROP COLUMN volume,
    DROP COLUMN chapter;

ALTER TABLE watch_ready
    DROP COLUMN action_id,
    DROP COLUMN marked_at,
    DROP COLUMN auto_mark;
