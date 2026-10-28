import AaruCore
import Foundation
@testable import aaru

extension UntouchedStore: ShareStore {
    func createShare(_: Share) async throws {
        throw Touched()
    }

    func share(code _: String) async throws -> Share? {
        throw Touched()
    }

    func existingShare(sender _: UserID, target _: ShareTarget, note _: String?) async throws -> Share? {
        throw Touched()
    }
}
