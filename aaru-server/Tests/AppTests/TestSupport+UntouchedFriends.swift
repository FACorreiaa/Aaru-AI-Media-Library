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

extension UntouchedStore: InteractionStore {
    func reactions(on _: [ActivityKey], viewer _: UserID) async throws -> [ActivityKey: ReactionSummary] {
        throw Touched()
    }

    func react(_: String?, on _: ActivityKey, by _: UserID, now _: Date) async throws {
        throw Touched()
    }

    func hasTitle(_: UserID, _: TitleID) async throws -> Bool {
        throw Touched()
    }

    func recommend(_: [Recommendation]) async throws {
        throw Touched()
    }

    func inbox(_: UserID, limit _: Int) async throws -> [Recommendation] {
        throw Touched()
    }

    func resolve(_: UUID, to _: UserID, added _: Bool, now _: Date) async throws -> Recommendation? {
        throw Touched()
    }
}
