import AaruCore
import Foundation
@testable import aaru

extension UntouchedStore: TonightStore {
    func reading(userID _: UserID, limit _: Int) async throws -> [ReadingEntry] {
        throw Touched()
    }

    func itemDates(_: [LibraryItemID], userID _: UserID) async throws -> [LibraryItemID: ItemDates] {
        throw Touched()
    }

    func feedback(userID _: UserID, since _: Date) async throws -> [TonightFeedback] {
        throw Touched()
    }

    func saveFeedback(_: TonightFeedback, userID _: UserID) async throws -> TonightFeedback? {
        throw Touched()
    }

    func recordPicks(_: [LibraryItemID], day _: LocalDay, userID _: UserID, servedAt _: Date) async throws -> Bool {
        throw Touched()
    }
}
