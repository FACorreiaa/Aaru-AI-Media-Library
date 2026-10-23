import AaruCore
import Foundation

/// BIL-001 · one App Store subscription, as Aaru keeps it.
struct Entitlement: Equatable, Sendable {
    var originalTransactionID: String
    var userID: UserID
    var productID: String
    /// Apple's `Production` or `Sandbox` (TestFlight buys in the sandbox).
    var environment: String
    var expiresAt: Date?
    var revokedAt: Date?
    /// When Apple signed this state.
    var signedAt: Date

    func isActive(at now: Date) -> Bool {
        revokedAt == nil && (expiresAt.map { $0 > now } ?? true)
    }
}

enum EntitlementWrite: Equatable, Sendable {
    /// The first time this subscription was seen.
    case inserted
    case updated
    /// The stored state was signed later; nothing changed.
    case stale
}

protocol EntitlementStore: Sendable {
    func record(_ entitlement: Entitlement, now: Date) async throws -> EntitlementWrite
    /// The subscription keeping the user on Plus at `now`, the one lasting longest; nil on the free tier.
    func active(userID: UserID, now: Date) async throws -> Entitlement?
    /// The account a subscription belongs to, if Aaru has seen it.
    func owner(originalTransactionID: String) async throws -> UserID?
}

/// One signed App Store transaction (`JWSTransactionDecodedPayload`), the fields Aaru reads.
struct AppleTransaction: Equatable, Sendable {
    var originalTransactionID: String
    var transactionID: String
    var bundleID: String
    var productID: String
    var environment: String
    /// The UUID the app set at purchase: the buyer's Aaru user id.
    var appAccountToken: UUID?
    var expiresAt: Date?
    var revokedAt: Date?
    var signedAt: Date
}

/// One App Store Server Notification v2 (`ResponseBodyV2DecodedPayload`).
struct AppleNotification: Equatable, Sendable {
    var type: String
    var subtype: String?
    var bundleID: String?
    /// The transaction it concerns, already verified; nil for a notification without one (TEST).
    var transaction: AppleTransaction?
}

/// Verifies Apple's signed data: the chain up to Apple's root, then the signature.
protocol AppleSignedDataVerifying: Sendable {
    func transaction(_ jws: String) async throws -> AppleTransaction
    func notification(_ jws: String) async throws -> AppleNotification
}
