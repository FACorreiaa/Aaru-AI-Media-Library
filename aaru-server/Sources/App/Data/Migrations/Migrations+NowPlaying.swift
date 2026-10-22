import FluentKit
import FluentSQL

/// SCR-008 · Live Activities the server starts, updates and ends from scrobbles. A device hands
/// over one push-to-start token (`start`), and each running activity its own token (`update`),
/// tied to the watch event it follows. A watch event is push-started at most once.
struct AddLiveActivities: SQLMigration {
    let forward = [
        """
        CREATE TABLE live_activity_tokens (
            token text PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            kind text NOT NULL CHECK (kind IN ('start', 'update')),
            environment text NOT NULL CHECK (environment IN ('sandbox', 'production')),
            topic text NOT NULL,
            watch_event_id uuid REFERENCES watch_events(id) ON DELETE CASCADE,
            updated_at timestamptz NOT NULL,
            CHECK ((kind = 'update') = (watch_event_id IS NOT NULL))
        )
        """,
        "CREATE INDEX live_activity_tokens_user ON live_activity_tokens (user_id, kind)",
        "CREATE INDEX live_activity_tokens_event ON live_activity_tokens (watch_event_id)",
        "ALTER TABLE watch_events ADD COLUMN live_activity_started_at timestamptz",
    ]
    let backward = [
        "ALTER TABLE watch_events DROP COLUMN live_activity_started_at",
        "DROP TABLE live_activity_tokens",
    ]
}

/// SCR-009 · One "Now playing" activity per device shows everything that plays. `live_plays` holds
/// what plays that is not a Title (a scrobbler's `playing_now` track, a YouTube video): one row per
/// connection and kind, replaced by the next report and gone once it expires. `live_activity_states`
/// keeps what the user's activity last showed, so a report pushes only when that changes, and when
/// the sweep must look again. Activity tokens now belong to the user, not to a watch event.
struct AddLivePlays: SQLMigration {
    let forward = [
        """
        CREATE TABLE live_plays (
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            agent_token_id uuid NOT NULL REFERENCES agent_tokens(id) ON DELETE CASCADE,
            kind text NOT NULL CHECK (kind IN ('track', 'video')),
            id uuid NOT NULL UNIQUE,
            source text NOT NULL CHECK (source IN ('listenbrainz', 'youtube')),
            ref text NOT NULL,
            title text NOT NULL,
            subtitle text,
            service text,
            artwork_url text,
            origin_url text,
            state text NOT NULL CHECK (state IN ('playing', 'paused')),
            position_ms bigint NOT NULL,
            duration_ms bigint NOT NULL,
            started_at timestamptz NOT NULL,
            updated_at timestamptz NOT NULL,
            expires_at timestamptz NOT NULL,
            PRIMARY KEY (user_id, kind, agent_token_id)
        )
        """,
        """
        CREATE TABLE live_activity_states (
            user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            pushed jsonb,
            lingering jsonb NOT NULL DEFAULT '[]',
            version integer NOT NULL DEFAULT 0,
            next_check_at timestamptz
        )
        """,
        "CREATE INDEX live_activity_states_due ON live_activity_states (next_check_at) WHERE next_check_at IS NOT NULL",
        // Tokens for the old per-episode activity point at nothing the app still shows.
        "DELETE FROM live_activity_tokens",
        "ALTER TABLE live_activity_tokens DROP COLUMN watch_event_id",
        "ALTER TABLE watch_events DROP COLUMN live_activity_started_at",
    ]
    let backward = [
        "ALTER TABLE watch_events ADD COLUMN live_activity_started_at timestamptz",
        "ALTER TABLE live_activity_tokens ADD COLUMN watch_event_id uuid REFERENCES watch_events(id) ON DELETE CASCADE",
        "DROP TABLE live_activity_states",
        "DROP TABLE live_plays",
    ]
}
