/// Server audit (docs/audit/server.md) · indexes the hot paths and foreign keys were missing.
/// Additive only: no table, column or row changes.
///
/// - `group_messages.reply_to`: `ON DELETE SET NULL` looks up the replies of every message a
///   channel or group delete removes. Without it, deleting a channel with 1,800 messages scanned
///   the whole table once per message (SRV-001).
/// - `library_items.title_id`, `list_items.title_id`: "is this title on anyone's shelf", asked by
///   every catalog backfill pass and the airing notifier. Only `(user_id, title_id)` existed.
/// - `watch_events (user_id, source, external_ref, stopped_at)`: the scrobble stop's "already
///   stopped a moment ago" check, once per stop.
/// - The rest back foreign keys an account or channel delete walks (agent tokens, invites,
///   watch parties), and the watch channel's "latest party".
struct AddAuditIndexes: SQLMigration {
    let forward = [
        "CREATE INDEX group_messages_reply_to ON group_messages (reply_to) WHERE reply_to IS NOT NULL",
        "CREATE INDEX library_items_title ON library_items (title_id)",
        "CREATE INDEX list_items_title ON list_items (title_id)",
        "CREATE INDEX agent_replies_channel ON agent_replies (channel_id)",
        "CREATE INDEX watch_events_stopped ON watch_events (user_id, source, external_ref, stopped_at)",
        "CREATE INDEX actions_agent_token ON actions (agent_token_id) WHERE agent_token_id IS NOT NULL",
        "CREATE INDEX watch_events_agent_token ON watch_events (agent_token_id) WHERE agent_token_id IS NOT NULL",
        "CREATE INDEX agent_plans_token ON agent_plans (agent_token_id) WHERE agent_token_id IS NOT NULL",
        "CREATE INDEX oauth_codes_user ON oauth_codes (user_id)",
        "CREATE INDEX oauth_codes_token ON oauth_codes (agent_token_id) WHERE agent_token_id IS NOT NULL",
        "CREATE INDEX group_invites_inviter ON group_invites (inviter_id)",
        "CREATE INDEX watch_ready_user ON watch_ready (user_id)",
        "CREATE INDEX watch_sessions_channel ON watch_sessions (channel_id, created_at DESC)",
    ]
    let backward = [
        "DROP INDEX watch_sessions_channel",
        "DROP INDEX watch_ready_user",
        "DROP INDEX group_invites_inviter",
        "DROP INDEX oauth_codes_token",
        "DROP INDEX oauth_codes_user",
        "DROP INDEX agent_plans_token",
        "DROP INDEX watch_events_agent_token",
        "DROP INDEX actions_agent_token",
        "DROP INDEX watch_events_stopped",
        "DROP INDEX agent_replies_channel",
        "DROP INDEX list_items_title",
        "DROP INDEX library_items_title",
        "DROP INDEX group_messages_reply_to",
    ]
}
