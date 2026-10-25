import AaruCore
import Foundation
@testable import aaru

extension UntouchedStore: SportsStore {
    func follows(userID _: UserID) async throws -> [SportFollow] {
        throw Touched()
    }

    func follow(_: SportEntity, userID _: UserID, limit _: Int, now _: Date) async throws -> Bool {
        throw Touched()
    }

    func unfollow(kind _: SportEntityKind, id _: String, userID _: UserID) async throws {
        throw Touched()
    }

    func watchCountry(userID _: UserID) async throws -> String? {
        throw Touched()
    }

    func saveWatchCountry(_: String?, userID _: UserID, now _: Date) async throws {
        throw Touched()
    }
}
