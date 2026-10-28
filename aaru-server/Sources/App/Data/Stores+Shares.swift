import AaruCore
import Foundation

/// What a share link points at (SHR-002): one catalog title, or one provider event by its id.
/// Nothing about an event is stored; it is read through the shared caches when the link opens.
enum ShareTarget: Sendable, Equatable {
    case title(TitleID)
    /// TheSportsDB's event id.
    case sportEvent(String)
    /// Ticketmaster's event id.
    case concert(String)

    var kind: String {
        switch self {
        case .title: "title"
        case .sportEvent: "sport_event"
        case .concert: "concert"
        }
    }
}

/// One share link (SHR-002): public and reusable. The sender is nil once their account is gone.
struct Share: Sendable, Equatable {
    var code: String
    var senderID: UserID?
    var target: ShareTarget
    var note: String?
    var createdAt: Date
}

protocol ShareStore: Sendable {
    /// Inserts a link. `StoreConflict` when the code is taken.
    func createShare(_ share: Share) async throws
    func share(code: String) async throws -> Share?
    /// The sender's newest link to this target with exactly this note (nil matches nil).
    func existingShare(sender: UserID, target: ShareTarget, note: String?) async throws -> Share?
}
