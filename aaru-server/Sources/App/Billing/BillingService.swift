import AaruCore
import Foundation
import HTTPTypes

/// BIL-001…003 · Aaru Plus, bought in the App Store and kept by the server. The app sends each
/// signed transaction after a purchase or a restore; Apple's notifications carry renewals,
/// expiries and refunds. The web reads the same state and sells nothing.
struct BillingService: Sendable {
    let stores: Stores
    /// Nil when billing is not configured; purchases then answer 503.
    let apple: (any AppleSignedDataVerifying)?
    var now: @Sendable () -> Date = { Date() }

    /// What `/v1/me/entitlement` reports.
    struct State: Equatable, Sendable {
        var plus: Entitlement?
        var capturesUsed: Int
        /// Nil on Plus: the monthly limit is lifted (a fair-use cap per day still applies).
        var captureLimit: Int?
        var capturesResetAt: Date
    }

    func state(userID: UserID) async throws -> State {
        let plus = try await stores.entitlements.active(userID: userID, now: now())
        let month = ImportService.monthStart(now())
        let used = try await stores.capture.captures(userID: userID, since: month.start)
        return State(
            plus: plus, capturesUsed: used, captureLimit: plus == nil ? ImportService.freeCapturesPerMonth : nil,
            capturesResetAt: month.next
        )
    }

    /// A purchase or a restore, from the app that made it. The transaction must name this account.
    func recordPurchase(_ jws: String, userID: UserID) async throws -> State {
        guard let apple else {
            throw AppError(
                status: .serviceUnavailable, code: "billing_unavailable",
                message: "Aaru cannot confirm purchases right now. Try again later; nothing was lost."
            )
        }
        let transaction: AppleTransaction
        do {
            transaction = try await apple.transaction(jws)
        } catch {
            throw AppError(
                status: .unprocessableContent, code: "invalid_transaction",
                message: "Aaru could not confirm that purchase with the App Store."
            )
        }
        guard transaction.appAccountToken == userID.rawValue else {
            throw AppError(
                status: .conflict, code: "plus_other_account",
                message: "This App Store purchase belongs to another Aaru account. Sign in with that account to use it."
            )
        }
        try await apply(transaction, userID: userID)
        return try await state(userID: userID)
    }

    /// One App Store Server Notification. A subscription Aaru cannot place (no account token, an
    /// account since deleted) is acknowledged and dropped, so Apple stops retrying it.
    func notify(_ jws: String) async throws {
        guard let apple else {
            throw AppError(status: .serviceUnavailable, code: "billing_unavailable", message: "Billing is off.")
        }
        let notification: AppleNotification
        do {
            notification = try await apple.notification(jws)
        } catch {
            throw AppError(
                status: .unprocessableContent, code: "invalid_notification", message: "The signature did not verify."
            )
        }
        guard let transaction = notification.transaction else { return }
        let known = try await stores.entitlements.owner(originalTransactionID: transaction.originalTransactionID)
        guard let userID = known ?? transaction.appAccountToken.map(UserID.init),
              try await stores.users.profile(userID) != nil
        else { return }
        try await apply(transaction, userID: userID)
    }

    private func apply(_ transaction: AppleTransaction, userID: UserID) async throws {
        let entitlement = Entitlement(
            originalTransactionID: transaction.originalTransactionID, userID: userID,
            productID: transaction.productID, environment: transaction.environment,
            expiresAt: transaction.expiresAt, revokedAt: transaction.revokedAt, signedAt: transaction.signedAt
        )
        let write = try await stores.entitlements.record(entitlement, now: now())
        if write == .inserted, entitlement.isActive(at: now()) {
            ProductEvents.capture(.plusPurchased, userID: userID, ["product": transaction.productID])
        }
    }
}
