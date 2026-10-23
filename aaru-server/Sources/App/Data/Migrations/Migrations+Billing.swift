import FluentKit
import FluentSQL

/// BIL-001 · Aaru Plus, bought in the App Store. One row per subscription (Apple's original
/// transaction id), owned by the account whose id the app set as the purchase's
/// `appAccountToken`. `signed_at` is the newest signed state applied, so a late notification
/// never overwrites a newer one. Plus is active while a row is unrevoked and unexpired.
struct AddEntitlements: SQLMigration {
    let forward = [
        """
        CREATE TABLE entitlements (
            original_transaction_id text PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            product_id text NOT NULL,
            environment text NOT NULL,
            expires_at timestamptz,
            revoked_at timestamptz,
            signed_at timestamptz NOT NULL,
            updated_at timestamptz NOT NULL
        )
        """,
        "CREATE INDEX entitlements_user ON entitlements (user_id)",
    ]
    let backward = [
        "DROP TABLE entitlements",
    ]
}
