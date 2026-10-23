import FluentKit
import FluentSQL

/// AG-005 · Tonight on the server. `tonight_picks` is what the strip showed on a local day, kept so
/// progress on a pick within six hours counts as taken (`accepted_at`). `tonight_feedback` is the
/// user's "not tonight" (that day only) and "not for me" (weighs for 14 days): their own data,
/// never read across users.
struct AddTonight: SQLMigration {
    let forward = [
        """
        CREATE TABLE tonight_picks (
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            day date NOT NULL,
            library_item_id uuid NOT NULL REFERENCES library_items(id) ON DELETE CASCADE,
            rank smallint NOT NULL,
            served_at timestamptz NOT NULL,
            accepted_at timestamptz,
            PRIMARY KEY (user_id, day, library_item_id)
        )
        """,
        "CREATE INDEX tonight_picks_item ON tonight_picks (library_item_id, served_at)",
        """
        CREATE TABLE tonight_feedback (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            library_item_id uuid NOT NULL REFERENCES library_items(id) ON DELETE CASCADE,
            verdict text NOT NULL CHECK (verdict IN ('rejected', 'not_tonight')),
            day date NOT NULL,
            created_at timestamptz NOT NULL
        )
        """,
        "CREATE INDEX tonight_feedback_user ON tonight_feedback (user_id, created_at)",
    ]
    let backward = [
        "DROP TABLE tonight_feedback",
        "DROP TABLE tonight_picks",
    ]
}
