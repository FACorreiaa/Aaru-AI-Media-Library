import FluentKit

/// GRP-012 · group push. Mentions and invites are their own switches next to `airing`, off until
/// the user turns them on like airing, and a member can mute one group. The alert never carries
/// message text, so nothing here stores any.
struct AddGroupPush: SQLMigration {
    let forward = [
        """
        ALTER TABLE notification_settings
            ADD COLUMN group_mentions boolean NOT NULL DEFAULT false,
            ADD COLUMN group_invites boolean NOT NULL DEFAULT false
        """,
        "ALTER TABLE group_members ADD COLUMN muted boolean NOT NULL DEFAULT false",
    ]
    let backward = [
        "ALTER TABLE group_members DROP COLUMN muted",
        "ALTER TABLE notification_settings DROP COLUMN group_invites, DROP COLUMN group_mentions",
    ]
}
