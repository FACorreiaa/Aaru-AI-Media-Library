import FluentKit

/// GRP-001 / GRP-002 / GRP-003 (pulled forward 2026-10-20) · groups, members, invites, text
/// channels, messages and read state.
///
/// Ownership is the one member row with role `owner`; there is no owner column to drift from it.
/// An invite exists only while it is pending, like a friend request. Messages are server-visible
/// by the owner's decision: a deleted message keeps its row with an empty body, and deleting an
/// account empties its messages before the author column goes null (`PostgresUserStore`).
/// Unread counts come from `last_read_at`, never from a stored counter.
struct CreateGroups: SQLMigration {
    let forward = [
        """
        CREATE TABLE groups (
            id uuid PRIMARY KEY,
            name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 50),
            created_at timestamptz NOT NULL,
            updated_at timestamptz NOT NULL
        )
        """,
        """
        CREATE TABLE group_members (
            group_id uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            role text NOT NULL CHECK (role IN ('owner', 'admin', 'member')),
            joined_at timestamptz NOT NULL,
            PRIMARY KEY (group_id, user_id)
        )
        """,
        "CREATE INDEX group_members_user ON group_members (user_id)",
        "CREATE UNIQUE INDEX group_members_one_owner ON group_members (group_id) WHERE role = 'owner'",
        """
        CREATE TABLE group_invites (
            id uuid PRIMARY KEY,
            group_id uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            inviter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            invitee_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            created_at timestamptz NOT NULL,
            CHECK (inviter_id <> invitee_id),
            UNIQUE (group_id, invitee_id)
        )
        """,
        "CREATE INDEX group_invites_invitee ON group_invites (invitee_id)",
        """
        CREATE TABLE group_channels (
            id uuid PRIMARY KEY,
            group_id uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
            kind text NOT NULL CHECK (kind IN ('text')),
            name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 32 AND name !~ '\\s'),
            topic text CHECK (char_length(topic) <= 200),
            position integer NOT NULL,
            is_default boolean NOT NULL DEFAULT false,
            created_at timestamptz NOT NULL,
            UNIQUE (group_id, name)
        )
        """,
        "CREATE UNIQUE INDEX group_channels_one_default ON group_channels (group_id) WHERE is_default",
        """
        CREATE TABLE group_messages (
            id uuid PRIMARY KEY,
            channel_id uuid NOT NULL REFERENCES group_channels(id) ON DELETE CASCADE,
            author_id uuid REFERENCES users(id) ON DELETE SET NULL,
            body text NOT NULL CHECK (char_length(body) <= 4000),
            mentions uuid[] NOT NULL DEFAULT '{}',
            mentions_agent boolean NOT NULL DEFAULT false,
            client_nonce text CHECK (char_length(client_nonce) <= 64),
            created_at timestamptz NOT NULL,
            edited_at timestamptz,
            deleted_at timestamptz,
            UNIQUE (author_id, client_nonce)
        )
        """,
        "CREATE INDEX group_messages_channel ON group_messages (channel_id, created_at DESC, id DESC)",
        "CREATE INDEX group_messages_author ON group_messages (author_id)",
        """
        CREATE TABLE group_read_state (
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            channel_id uuid NOT NULL REFERENCES group_channels(id) ON DELETE CASCADE,
            last_read_at timestamptz NOT NULL,
            PRIMARY KEY (user_id, channel_id)
        )
        """,
    ]
    let backward = [
        "DROP TABLE group_read_state",
        "DROP TABLE group_messages",
        "DROP TABLE group_channels",
        "DROP TABLE group_invites",
        "DROP TABLE group_members",
        "DROP TABLE groups",
    ]
}
