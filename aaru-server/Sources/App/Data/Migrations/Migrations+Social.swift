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

/// SOC-002 · friend invite links. One link per invite: whoever opens it first while it is live
/// becomes the inviter's friend, and it is spent. A link may carry one title the inviter wants
/// to watch with them ("Watch Severance with me"); the invitee chooses whether to add it.
struct AddFriendInvites: SQLMigration {
    let forward = [
        """
        CREATE TABLE social_invites (
            id uuid PRIMARY KEY,
            code text NOT NULL UNIQUE,
            inviter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            title_id uuid REFERENCES titles(id) ON DELETE RESTRICT,
            created_at timestamptz NOT NULL,
            expires_at timestamptz NOT NULL,
            redeemed_by uuid REFERENCES users(id) ON DELETE SET NULL,
            redeemed_at timestamptz,
            revoked_at timestamptz,
            CHECK (redeemed_by IS NULL OR redeemed_by <> inviter_id)
        )
        """,
        "CREATE INDEX social_invites_inviter ON social_invites (inviter_id, created_at DESC)",
    ]
    let backward = [
        "DROP TABLE social_invites",
    ]
}

/// SOC-001 · social settings. A missing row means the defaults: friends see your library. Strangers
/// never see anything, whatever is stored here.
struct AddSocialSettings: SQLMigration {
    let forward = [
        """
        CREATE TABLE social_settings (
            user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            share_library_with_friends boolean NOT NULL DEFAULT true,
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """,
    ]
    let backward = [
        "DROP TABLE social_settings",
    ]
}

/// SOC-007 reactions and SOC-006 recommendations. A reaction is on one activity row: a friend's
/// title on one UTC day, as `/v1/activity` groups it. A recommendation waits in the recipient's
/// inbox until they add it to Plan to watch or dismiss it.
struct AddSocialInteractions: SQLMigration {
    let forward = [
        """
        CREATE TABLE social_reactions (
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            owner_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            title_id uuid NOT NULL REFERENCES titles(id) ON DELETE CASCADE,
            day date NOT NULL,
            emoji text NOT NULL CHECK (emoji IN ('❤️', '😂', '😮', '😭', '🔥', '👏')),
            created_at timestamptz NOT NULL,
            PRIMARY KEY (user_id, owner_id, title_id, day)
        )
        """,
        "CREATE INDEX social_reactions_row ON social_reactions (owner_id, title_id, day)",
        """
        CREATE TABLE social_recommendations (
            id uuid PRIMARY KEY,
            from_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            to_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            title_id uuid NOT NULL REFERENCES titles(id) ON DELETE CASCADE,
            note text CHECK (char_length(note) <= 140),
            created_at timestamptz NOT NULL,
            added_at timestamptz,
            dismissed_at timestamptz,
            CHECK (from_user_id <> to_user_id)
        )
        """,
        """
        CREATE UNIQUE INDEX social_recommendations_open ON social_recommendations (from_user_id, to_user_id, title_id)
        WHERE added_at IS NULL AND dismissed_at IS NULL
        """,
        "CREATE INDEX social_recommendations_inbox ON social_recommendations (to_user_id, created_at DESC)",
    ]
    let backward = [
        "DROP TABLE social_recommendations",
        "DROP TABLE social_reactions",
    ]
}
