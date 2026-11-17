-- Worlds (GRAPH-007, owner 2026-11-17): one story universe across every kind, the connected set of
-- titles the relation graph joins. The relation cache (`catalog_relations`) is one answer per
-- provider node and cannot be walked in SQL, and listing a user's Worlds cannot pay for a graph
-- walk per library title, so a World's membership is stored once it is built.
--
-- Catalog data, the same for every user: none of these tables has a user column. A World is
-- joined by provider ids (`world_keys`), never by name. `world_builds` is both the queue the
-- worker leases and the record that a title was looked at and has no World.

-- +goose Up
CREATE TABLE worlds (
    id uuid NOT NULL PRIMARY KEY,
    root_key text NOT NULL,
    name text NOT NULL,
    links jsonb NOT NULL,
    truncated boolean NOT NULL DEFAULT false,
    partial boolean NOT NULL DEFAULT false,
    title_count integer NOT NULL,
    built_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT worlds_root_key_key UNIQUE (root_key)
);

CREATE TABLE world_titles (
    world_id uuid NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    "position" integer NOT NULL,
    node_key text NOT NULL,
    lane text NOT NULL,
    lane_position integer NOT NULL,
    side boolean NOT NULL DEFAULT false,
    node jsonb NOT NULL,
    PRIMARY KEY (world_id, "position"),
    CONSTRAINT world_titles_lane_check CHECK ((lane = ANY (ARRAY['book'::text, 'manga'::text, 'film'::text, 'show'::text, 'anime'::text, 'album'::text])))
);

CREATE TABLE world_keys (
    node_key text NOT NULL PRIMARY KEY,
    world_id uuid NOT NULL REFERENCES worlds (id) ON DELETE CASCADE,
    "position" integer NOT NULL
);
CREATE INDEX world_keys_world_id ON world_keys USING btree (world_id);

CREATE TABLE world_builds (
    title_id uuid NOT NULL PRIMARY KEY REFERENCES titles (id) ON DELETE CASCADE,
    priority integer NOT NULL DEFAULT 0,
    state text NOT NULL,
    attempts integer NOT NULL DEFAULT 0,
    run_after timestamp with time zone NOT NULL,
    leased_until timestamp with time zone,
    checked_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    CONSTRAINT world_builds_state_check CHECK ((state = ANY (ARRAY['queued'::text, 'running'::text, 'done'::text, 'failed'::text])))
);
CREATE INDEX world_builds_queue ON world_builds USING btree (priority DESC, run_after) WHERE (state = 'queued'::text);
CREATE INDEX world_builds_running ON world_builds USING btree (leased_until) WHERE (state = 'running'::text);

-- +goose Down
DROP TABLE world_builds;
DROP TABLE world_keys;
DROP TABLE world_titles;
DROP TABLE worlds;
