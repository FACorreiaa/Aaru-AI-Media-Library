import AaruCore
import Foundation
@testable import aaru

extension UntouchedStore: CaptureStore {
    func saveInput(_: CaptureInput) async throws {
        throw Touched()
    }

    func input(jobID _: ImportJobID) async throws -> CaptureInput? {
        throw Touched()
    }

    func deleteInput(jobID _: ImportJobID) async throws {
        throw Touched()
    }

    func sweep(before _: Date) async throws -> Int {
        throw Touched()
    }

    func captures(userID _: UserID, since _: Date) async throws -> Int {
        throw Touched()
    }
}
