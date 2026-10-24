import FluentKit
import FluentSQL

/// APP-002 · a 6-digit code in every sign-in email, for apps that cannot open the link yet.
/// Stored hashed with its email; a link dies after `AuthService.maxCodeAttempts` wrong codes.
struct AddMagicLinkCodes: SQLMigration {
    let forward = [
        "ALTER TABLE magic_links ADD COLUMN code_hash text",
        "ALTER TABLE magic_links ADD COLUMN failed_attempts integer NOT NULL DEFAULT 0",
    ]
    let backward = [
        "ALTER TABLE magic_links DROP COLUMN failed_attempts",
        "ALTER TABLE magic_links DROP COLUMN code_hash",
    ]
}
