import AaruCore
import Foundation
@testable import aaru

extension UntouchedStore: EntitlementStore {
    func record(_: Entitlement, now _: Date) async throws -> EntitlementWrite {
        throw Touched()
    }

    func active(userID _: UserID, now _: Date) async throws -> Entitlement? {
        throw Touched()
    }

    func owner(originalTransactionID _: String) async throws -> UserID? {
        throw Touched()
    }
}
