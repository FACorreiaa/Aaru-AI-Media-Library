import AaruCore
import FluentSQL
import Foundation

/// App Store subscriptions (BIL-001). A write never replaces a state Apple signed later.
struct PostgresEntitlementStore: EntitlementStore {
    let sql: any SQLDatabase

    func record(_ entitlement: Entitlement, now: Date) async throws -> EntitlementWrite {
        struct Row: Decodable {
            let inserted: Bool
        }
        let row = try await sql.raw("""
        INSERT INTO entitlements (original_transaction_id, user_id, product_id, environment, expires_at, revoked_at,
                                  signed_at, updated_at)
        VALUES (\(bind: entitlement.originalTransactionID), \(bind: entitlement.userID.rawValue),
                \(bind: entitlement.productID), \(bind: entitlement.environment), \(bind: entitlement.expiresAt),
                \(bind: entitlement.revokedAt), \(bind: entitlement.signedAt), \(bind: now))
        ON CONFLICT (original_transaction_id) DO UPDATE SET
            product_id = EXCLUDED.product_id, environment = EXCLUDED.environment,
            expires_at = EXCLUDED.expires_at, revoked_at = EXCLUDED.revoked_at,
            signed_at = EXCLUDED.signed_at, updated_at = EXCLUDED.updated_at
        WHERE entitlements.signed_at <= EXCLUDED.signed_at
        RETURNING (xmax = 0) AS inserted
        """).first(decoding: Row.self)
        guard let row else { return .stale }
        return row.inserted ? .inserted : .updated
    }

    func active(userID: UserID, now: Date) async throws -> Entitlement? {
        struct Row: Decodable {
            let originalTransactionId: String
            let productId: String
            let environment: String
            let expiresAt: Date?
            let signedAt: Date
        }
        let row = try await sql.raw("""
        SELECT original_transaction_id, product_id, environment, expires_at, signed_at FROM entitlements
        WHERE user_id = \(bind: userID.rawValue) AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at > \(bind: now))
        ORDER BY expires_at DESC NULLS FIRST
        LIMIT 1
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        return row.map {
            Entitlement(
                originalTransactionID: $0.originalTransactionId, userID: userID, productID: $0.productId,
                environment: $0.environment, expiresAt: $0.expiresAt, revokedAt: nil, signedAt: $0.signedAt
            )
        }
    }

    func owner(originalTransactionID: String) async throws -> UserID? {
        struct Row: Decodable {
            let userId: UUID
        }
        return try await sql.raw("""
        SELECT user_id FROM entitlements WHERE original_transaction_id = \(bind: originalTransactionID)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map { UserID($0.userId) }
    }
}
