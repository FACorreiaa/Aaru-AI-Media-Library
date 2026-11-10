import AaruAPI
import Foundation

/// One Chat turn in the Assistant card: what was asked and Aaru's reply so far.
struct AssistantTurn: Identifiable {
    let id: UUID
    let question: String
    /// The names of the files it carried (ASK-010).
    var files: [String] = []
    let spoken: Bool
    var reply: ChatReply
    var undone: Bool
}

extension Notification.Name {
    /// Delete my chats succeeded. A notification because the Mac's Settings scene does not hold
    /// the model.
    static let aaruChatsDeleted = Notification.Name("aaruChatsDeleted")
    /// One chat was deleted; `object` is its id (ASK-011). The card and Settings each keep a list.
    static let aaruChatDeleted = Notification.Name("aaruChatDeleted")
}
