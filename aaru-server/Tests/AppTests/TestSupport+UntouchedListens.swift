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

    func stage(_: [NewListen], jobID _: ImportJobID, from _: Int) async throws {
        throw Touched()
    }

    func clearStaged(jobID _: ImportJobID) async throws {
        throw Touched()
    }

    func countNew(jobID _: ImportJobID, userID _: UserID) async throws -> Int {
        throw Touched()
    }

    func applyStaged(jobID _: ImportJobID, userID _: UserID) async throws -> Int {
        throw Touched()
    }

    func deleteImported(jobID _: ImportJobID, userID _: UserID) async throws -> Int {
        throw Touched()
    }

    func newestImported(userID _: UserID, source _: ImportSource, account _: String) async throws -> Date? {
        throw Touched()
    }
}
