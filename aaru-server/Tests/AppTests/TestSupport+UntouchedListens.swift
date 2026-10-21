import AaruCore
import Foundation
@testable import aaru

extension UntouchedStore: ListenStore {
    func insert(_: [NewListen], userID _: UserID, agentTokenID _: UUID?) async throws -> Int {
        throw Touched()
    }

    func listens(userID _: UserID, before _: Date?, limit _: Int) async throws -> [Listen] {
        throw Touched()
    }

    func top(userID _: UserID, by _: ListenGrouping, period _: StatsPeriod, limit _: Int, artist _: String?)
        async throws -> ListenTop
    {
        throw Touched()
    }

    func unresolved(retryBefore _: Date, limit _: Int) async throws -> [ListenLookup] {
        throw Touched()
    }

    func resolve(_: ListenLookup, as _: RecordingMatch, at _: Date) async throws -> Int {
        throw Touched()
    }
}
