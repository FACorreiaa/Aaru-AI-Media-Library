import FluentKit

/// SOC-001 / SOC-002 (minimal, pulled forward for groups) · handles, friends, blocks, reports.
///
/// A handle is lowercase by rule, so equality needs no `citext`. A friend request exists only
/// while it is pending: accepting turns it into a friendship, declining or cancelling deletes it.
/// A friendship is one row per pair with the smaller id first. Every user column cascades, so
/// deleting an account removes its whole social footprint; a report about a deleted user keeps
/// its reason and loses the target.
struct CreateSocial: SQLMigration {
    let forward = [
        """
        CREATE TABLE profiles (
            user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            handle text NOT NULL UNIQUE CHECK (handle ~ '^[a-z0-9_]{3,20}$'),
            created_at timestamptz NOT NULL DEFAULT now(),
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """,
        """
        CREATE TABLE social_friend_requests (
            id uuid PRIMARY KEY,
            from_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            to_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            created_at timestamptz NOT NULL,
            CHECK (from_user_id <> to_user_id),
            UNIQUE (from_user_id, to_user_id)
        )
        """,
        "CREATE INDEX social_friend_requests_to ON social_friend_requests (to_user_id)",
        """
        CREATE TABLE social_friendships (
            user_low uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            user_high uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            created_at timestamptz NOT NULL,
            PRIMARY KEY (user_low, user_high),
            CHECK (user_low < user_high)
        )
        """,
        "CREATE INDEX social_friendships_high ON social_friendships (user_high)",
        """
        CREATE TABLE social_blocks (
            blocker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            blocked_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            created_at timestamptz NOT NULL,
            PRIMARY KEY (blocker_id, blocked_id),
            CHECK (blocker_id <> blocked_id)
        )
        """,
        "CREATE INDEX social_blocks_blocked ON social_blocks (blocked_id)",
        """
        CREATE TABLE social_reports (
            id uuid PRIMARY KEY,
            reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            target_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
            reason text NOT NULL CHECK (reason IN ('spam', 'harassment', 'impersonation', 'other')),
            note text CHECK (char_length(note) <= 1000),
            created_at timestamptz NOT NULL
        )
        """,
    ]
    let backward = [
        "DROP TABLE social_reports",
        "DROP TABLE social_blocks",
        "DROP TABLE social_friendships",
        "DROP TABLE social_friend_requests",
        "DROP TABLE profiles",
    ]
}
