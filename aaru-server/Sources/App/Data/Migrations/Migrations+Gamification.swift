/// GAM-001…005 (owner pulled forward 2026-10-22): the points ledger, streak days, badges and the
/// two achievement settings. See ARCHITECTURE.md §Gamification.
///
/// - `points_events` is append-only. `dedupe_key` is `root#seq`: an award and its revocation
///   share a root, so undo then redo nets one award and a replay earns nothing twice.
/// - `user_progress` caches the total and holds the stored time zone and the worker's dirty flag;
///   it is rebuilt from the ledger, never the source.
/// - `check_ins` are streak days, written only by live progress.
/// - `user_badges` keeps one row per earned tier; `action_id` lets an undo take a tier back.
struct AddGamification: SQLMigration {
    let forward = [
        """
        CREATE TABLE points_events (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            kind text NOT NULL,
            points integer NOT NULL,
            dedupe_root text NOT NULL,
            seq integer NOT NULL CHECK (seq >= 1),
            dedupe_key text NOT NULL,
            reverses uuid REFERENCES points_events(id) ON DELETE CASCADE,
            title_id uuid REFERENCES titles(id) ON DELETE SET NULL,
            action_id uuid REFERENCES actions(id) ON DELETE SET NULL,
            local_date date NOT NULL,
            time_zone text NOT NULL,
            created_at timestamptz NOT NULL DEFAULT now(),
            UNIQUE (user_id, dedupe_key)
        )
        """,
        "CREATE INDEX points_events_root ON points_events (user_id, dedupe_root, seq DESC)",
        "CREATE INDEX points_events_day ON points_events (user_id, local_date)",
        "CREATE INDEX points_events_reverses ON points_events (reverses) WHERE reverses IS NOT NULL",
        """
        CREATE TABLE user_progress (
            user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            total_points integer NOT NULL DEFAULT 0,
            time_zone text,
            dirty_at timestamptz,
            dirty_origin text CHECK (dirty_origin IN ('live', 'batch', 'backfill')),
            locked_until timestamptz,
            evaluated_at timestamptz,
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """,
        "CREATE INDEX user_progress_dirty ON user_progress (dirty_at) WHERE dirty_at IS NOT NULL",
        """
        CREATE TABLE check_ins (
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            local_date date NOT NULL,
            time_zone text NOT NULL,
            first_at timestamptz NOT NULL,
            PRIMARY KEY (user_id, local_date)
        )
        """,
        """
        CREATE TABLE user_badges (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            badge text NOT NULL,
            tier integer NOT NULL CHECK (tier BETWEEN 1 AND 4),
            awarded_at timestamptz NOT NULL,
            origin text NOT NULL CHECK (origin IN ('live', 'batch', 'backfill')),
            action_id uuid REFERENCES actions(id) ON DELETE SET NULL,
            seen_at timestamptz,
            UNIQUE (user_id, badge, tier)
        )
        """,
        "CREATE INDEX user_badges_unseen ON user_badges (user_id) WHERE seen_at IS NULL",
        """
        ALTER TABLE social_settings
            ADD COLUMN show_achievements_to_friends boolean NOT NULL DEFAULT true,
            ADD COLUMN leaderboard_opt_in boolean NOT NULL DEFAULT false
        """,
    ]
    let backward = [
        "ALTER TABLE social_settings DROP COLUMN leaderboard_opt_in, DROP COLUMN show_achievements_to_friends",
        "DROP TABLE user_badges",
        "DROP TABLE check_ins",
        "DROP TABLE user_progress",
        "DROP TABLE points_events",
    ]
}
