import FluentSQL

/// BRD-001 Board: posts, comments, upvotes. Friends-only; visibility lives in BoardService.
struct CreateBoards: SQLMigration {
    let forward = [
        """
        CREATE TABLE board_posts (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            title_id uuid REFERENCES titles(id),
            rating numeric(3,1) CHECK (rating IS NULL OR title_id IS NOT NULL),
            body text NOT NULL CHECK (char_length(body) <= 4000),
            spoiler_season integer CHECK (spoiler_season >= 0),
            spoiler_episode integer CHECK (spoiler_episode >= 1),
            spoiler_ending boolean NOT NULL DEFAULT false,
            created_at timestamptz NOT NULL DEFAULT now(),
            edited_at timestamptz,
            deleted_at timestamptz,
            CONSTRAINT board_posts_spoiler_pair CHECK ((spoiler_season IS NULL) = (spoiler_episode IS NULL))
        )
        """,
        "CREATE INDEX board_posts_feed ON board_posts (created_at DESC, id DESC) WHERE deleted_at IS NULL",
        "CREATE INDEX board_posts_author ON board_posts (user_id, created_at DESC)",
        "CREATE INDEX board_posts_title ON board_posts (title_id) WHERE title_id IS NOT NULL",
        """
        CREATE TABLE board_upvotes (
            post_id uuid NOT NULL REFERENCES board_posts(id) ON DELETE CASCADE,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            created_at timestamptz NOT NULL DEFAULT now(),
            PRIMARY KEY (post_id, user_id)
        )
        """,
        """
        CREATE TABLE board_comments (
            id uuid PRIMARY KEY,
            post_id uuid NOT NULL REFERENCES board_posts(id) ON DELETE CASCADE,
            user_id uuid REFERENCES users(id) ON DELETE CASCADE,
            author_kind text NOT NULL CHECK (author_kind IN ('user', 'agent')),
            reply_to uuid REFERENCES board_comments(id) ON DELETE CASCADE,
            body text NOT NULL CHECK (char_length(body) <= 4000),
            mentions uuid[] NOT NULL DEFAULT '{}',
            mentions_agent boolean NOT NULL DEFAULT false,
            created_at timestamptz NOT NULL DEFAULT now(),
            deleted_at timestamptz,
            CONSTRAINT board_comments_author_bound CHECK ((author_kind = 'user') = (user_id IS NOT NULL))
        )
        """,
        "CREATE INDEX board_comments_post ON board_comments (post_id, created_at, id)",
    ]
    let backward = [
        "DROP TABLE board_comments",
        "DROP TABLE board_upvotes",
        "DROP TABLE board_posts",
    ]
}
