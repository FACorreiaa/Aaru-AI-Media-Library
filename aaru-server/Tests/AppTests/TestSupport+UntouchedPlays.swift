import AaruCore
import Foundation
@testable import aaru

/// `UntouchedStore`'s SCR-009 half of `WatchEventStore`: plays and the activity's state.
extension UntouchedStore {
    func forgetLiveActivityUpdates(userID _: UserID) async throws {
        throw Touched()
    }

    func savePlay(_: LivePlay, userID _: UserID, agentTokenID _: UUID) async throws {
        throw Touched()
    }

    func removePlay(_: LivePlay.Kind, userID _: UserID, agentTokenID _: UUID) async throws {
        throw Touched()
    }

    func livePlays(userID _: UserID, now _: Date) async throws -> [LivePlay] {
        throw Touched()
    }

    func liveActivityState(userID _: UserID) async throws -> LiveActivityState {
        throw Touched()
    }

    func saveLiveActivityState(_: LiveActivityState, userID _: UserID) async throws -> Bool {
        throw Touched()
    }

    func scheduleLiveActivityCheck(userID _: UserID, at _: Date) async throws {
        throw Touched()
    }

    func claimDueLiveActivityChecks(now _: Date, limit _: Int) async throws -> [UserID] {
        throw Touched()
    }
}
