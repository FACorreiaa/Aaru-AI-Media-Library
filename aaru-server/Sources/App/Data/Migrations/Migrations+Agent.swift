import FluentKit

/// GRP-010 / GRP-011 · `@aaru` in groups.
///
/// A group message is written by a user or by the agent; the agent's has no author row, a
/// `reply_to` naming the mention it answers, and `components` holding catalog cards only.
/// `agent_replies` is the job queue (one row per mention, leased like imports); a `capped` row
/// records a mention over the fair-use cap that got the one "resting" reply, and `skipped` one
/// that got nothing. `agent_usage` meters model spend per user per day from the first call.
struct AddAgentReplies: SQLMigration {
    let forward = [
        """
        ALTER TABLE group_messages
            ADD COLUMN author_kind text NOT NULL DEFAULT 'user' CHECK (author_kind IN ('user', 'agent')),
            ADD COLUMN reply_to uuid REFERENCES group_messages(id) ON DELETE SET NULL,
            ADD COLUMN components jsonb,
            ADD CONSTRAINT group_messages_agent_has_no_author
                CHECK (author_kind = 'user' OR author_id IS NULL)
        """,
        """
        CREATE TABLE agent_replies (
            id uuid PRIMARY KEY,
            message_id uuid NOT NULL UNIQUE REFERENCES group_messages(id) ON DELETE CASCADE,
            group_id uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            channel_id uuid NOT NULL REFERENCES group_channels(id) ON DELETE CASCADE,
            tagger_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            state text NOT NULL CHECK (state IN ('queued', 'running', 'done', 'failed', 'capped', 'skipped')),
            attempts integer NOT NULL DEFAULT 0,
            locked_until timestamptz,
            error text,
            created_at timestamptz NOT NULL,
            updated_at timestamptz NOT NULL
        )
        """,
        "CREATE INDEX agent_replies_queue ON agent_replies (state, created_at)",
        "CREATE INDEX agent_replies_tagger ON agent_replies (tagger_id, created_at)",
        "CREATE INDEX agent_replies_group ON agent_replies (group_id, created_at)",
        """
        CREATE TABLE agent_usage (
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            day date NOT NULL,
            requests integer NOT NULL DEFAULT 0,
            input_tokens bigint NOT NULL DEFAULT 0,
            output_tokens bigint NOT NULL DEFAULT 0,
            PRIMARY KEY (user_id, day)
        )
        """,
    ]
    let backward = [
        "DROP TABLE agent_usage",
        "DROP TABLE agent_replies",
        """
        ALTER TABLE group_messages DROP CONSTRAINT group_messages_agent_has_no_author,
            DROP COLUMN components, DROP COLUMN reply_to, DROP COLUMN author_kind
        """,
    ]
}
