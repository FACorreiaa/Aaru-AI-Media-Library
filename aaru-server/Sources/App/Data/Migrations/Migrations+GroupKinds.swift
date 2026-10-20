import FluentKit

/// GRP-007 / GRP-008 / GRP-009 · title, shelf and watch channels.
///
/// A `title` channel is bound to one title; `shelf` and `watch` channels are not (a shelf holds
/// many titles, a watch channel holds one session at a time). A message's spoiler stamp is an
/// episode, or "the ending" for anything; readers behind it see it veiled. `share_progress` is
/// per group and off by default. A watch session's state is derived: lobby until `starts_at`
/// is set, counting down until it passes, live until `ended_at`.
struct AddGroupChannelKinds: SQLMigration {
    let forward = [
        "ALTER TABLE group_channels DROP CONSTRAINT group_channels_kind_check",
        """
        ALTER TABLE group_channels
            ADD CONSTRAINT group_channels_kind_check CHECK (kind IN ('text', 'title', 'watch', 'shelf')),
            ADD COLUMN title_id uuid REFERENCES titles(id) ON DELETE RESTRICT,
            ADD CONSTRAINT group_channels_title_bound CHECK ((kind = 'title') = (title_id IS NOT NULL))
        """,
        "ALTER TABLE group_members ADD COLUMN share_progress boolean NOT NULL DEFAULT false",
        """
        ALTER TABLE group_messages
            ADD COLUMN spoiler_season integer CHECK (spoiler_season >= 0),
            ADD COLUMN spoiler_episode integer CHECK (spoiler_episode >= 1),
            ADD COLUMN spoiler_ending boolean NOT NULL DEFAULT false,
            ADD CONSTRAINT group_messages_spoiler_pair CHECK ((spoiler_season IS NULL) = (spoiler_episode IS NULL))
        """,
        """
        CREATE TABLE group_channel_items (
            channel_id uuid NOT NULL REFERENCES group_channels(id) ON DELETE CASCADE,
            title_id uuid NOT NULL REFERENCES titles(id) ON DELETE RESTRICT,
            added_by uuid REFERENCES users(id) ON DELETE SET NULL,
            position integer NOT NULL,
            added_at timestamptz NOT NULL,
            PRIMARY KEY (channel_id, title_id)
        )
        """,
        """
        CREATE TABLE watch_sessions (
            id uuid PRIMARY KEY,
            channel_id uuid NOT NULL REFERENCES group_channels(id) ON DELETE CASCADE,
            title_id uuid NOT NULL REFERENCES titles(id) ON DELETE RESTRICT,
            season integer CHECK (season >= 0),
            episode integer CHECK (episode >= 1),
            created_by uuid REFERENCES users(id) ON DELETE SET NULL,
            starts_at timestamptz,
            ended_at timestamptz,
            created_at timestamptz NOT NULL,
            CHECK ((season IS NULL) = (episode IS NULL))
        )
        """,
        "CREATE UNIQUE INDEX watch_sessions_one_open ON watch_sessions (channel_id) WHERE ended_at IS NULL",
        """
        CREATE TABLE watch_ready (
            session_id uuid NOT NULL REFERENCES watch_sessions(id) ON DELETE CASCADE,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            PRIMARY KEY (session_id, user_id)
        )
        """,
    ]
    let backward = [
        "DROP TABLE watch_ready",
        "DROP TABLE watch_sessions",
        "DROP TABLE group_channel_items",
        """
        ALTER TABLE group_messages DROP CONSTRAINT group_messages_spoiler_pair,
            DROP COLUMN spoiler_season, DROP COLUMN spoiler_episode, DROP COLUMN spoiler_ending
        """,
        "ALTER TABLE group_members DROP COLUMN share_progress",
        """
        ALTER TABLE group_channels DROP CONSTRAINT group_channels_title_bound, DROP COLUMN title_id,
            DROP CONSTRAINT group_channels_kind_check
        """,
        "ALTER TABLE group_channels ADD CONSTRAINT group_channels_kind_check CHECK (kind IN ('text'))",
    ]
}
