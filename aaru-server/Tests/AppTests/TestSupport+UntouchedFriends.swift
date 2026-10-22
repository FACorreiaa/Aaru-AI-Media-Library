import AaruCore
import Foundation
@testable import aaru

extension UntouchedStore: FriendViewStore {
    func socialSettings(_: UserID) async throws -> SocialSettings {
        throw Touched()
    }

    func saveSocialSettings(_: SocialSettings, for _: UserID) async throws {
        throw Touched()
    }

    func friendsSince(_: UserID, _: UserID) async throws -> Date? {
        throw Touched()
    }

    func shelf(of _: UserID, viewer _: UserID, limit _: Int) async throws -> FriendShelf {
        throw Touched()
    }

    func activity(viewer _: UserID, since _: Date, before _: Date, limit _: Int) async throws -> [FriendActivity] {
        throw Touched()
    }
}
