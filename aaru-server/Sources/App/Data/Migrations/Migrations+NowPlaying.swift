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
