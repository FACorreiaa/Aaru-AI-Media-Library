import FluentKit

/// SOC-001b (owner, 2026-10-27) · first and last name, the avatar, and sharing the email.
///
/// `display_name` stays: it is the two names joined, so every reader of it (groups, invites, the
/// agent) is unchanged. Existing names split at the first space; users fix theirs by hand.
/// `avatar_version` is null without an avatar and changes on every upload, so a URL carrying it
/// is never stale; the bytes live apart in `avatars` so profile reads never load them.
struct AddProfileDetails: SQLMigration {
    let forward = [
        "ALTER TABLE users ADD COLUMN first_name text, ADD COLUMN last_name text, ADD COLUMN avatar_version bigint",
        #"""
        UPDATE users SET
            first_name = substring(btrim(display_name) FROM '^\S+'),
            last_name = nullif(btrim(regexp_replace(btrim(display_name), '^\S+', '')), '')
        WHERE nullif(btrim(display_name), '') IS NOT NULL
        """#,
        """
        CREATE TABLE avatars (
            user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            image bytea NOT NULL CHECK (octet_length(image) <= 1048576),
            updated_at timestamptz NOT NULL DEFAULT now()
        )
        """,
        "ALTER TABLE social_settings ADD COLUMN share_email_with_friends boolean NOT NULL DEFAULT false",
    ]
    let backward = [
        "ALTER TABLE social_settings DROP COLUMN share_email_with_friends",
        "DROP TABLE avatars",
        "ALTER TABLE users DROP COLUMN avatar_version, DROP COLUMN last_name, DROP COLUMN first_name",
    ]
}
