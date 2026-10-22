import AaruCore
import Foundation
@testable import aaru

/// SOC-002 invite links, apart from `UntouchedStore`'s social half for the file-length limit.
extension UntouchedStore {
    func createInvite(_: FriendInvite) async throws {
        throw Touched()
    }

    func invite(code _: String) async throws -> FriendInvite? {
        throw Touched()
    }

    func openInvites(_: UserID, now _: Date) async throws -> [FriendInvite] {
        throw Touched()
    }

    func revokeInvite(code _: String, inviter _: UserID, now _: Date) async throws -> Bool {
        throw Touched()
    }

    func redeemInvite(code _: String, redeemer _: UserID, now _: Date) async throws -> UserID? {
        throw Touched()
    }
}
