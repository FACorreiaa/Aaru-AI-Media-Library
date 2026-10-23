import AaruCore
import Foundation

/// What a capture sent, kept only until the worker has read the titles out of it (AG-006).
struct CaptureInput: Sendable, Equatable {
    enum Content: Sendable, Equatable {
        case text(String)
        /// One image, as uploaded: JPEG, PNG, GIF or WebP.
        case image(Data, mediaType: String)
    }

    var jobID: ImportJobID
    var userID: UserID
    var content: Content
    var createdAt: Date

    var kind: String {
        switch content {
        case .text: "text"
        case .image: "image"
        }
    }
}

protocol CaptureStore: Sendable {
    func saveInput(_ input: CaptureInput) async throws
    func input(jobID: ImportJobID) async throws -> CaptureInput?
    func deleteInput(jobID: ImportJobID) async throws
    /// Deletes every input written before `before`; returns how many.
    func sweep(before: Date) async throws -> Int
    /// The user's capture jobs started at or after `since`, failed ones included.
    func captures(userID: UserID, since: Date) async throws -> Int
}
