import Foundation

/// One file in a Chat with Aaru (ASK-010), as the server read it: what it is and what its chip says.
public struct ChatFile: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: Kind
    public let name: String
    /// "a Letterboxd export of 412 rows"
    public let summary: String

    public enum Kind: String, Sendable {
        case image, pdf, text, export, listens
    }

    public init(id: String, kind: Kind, name: String, summary: String) {
        self.id = id
        self.kind = kind
        self.name = name
        self.summary = summary
    }

    init(_ file: Components.Schemas.ChatAttachment) {
        self.init(
            id: file.id, kind: Kind(rawValue: file.kind.rawValue) ?? .text, name: file.name, summary: file.summary
        )
    }
}

/// A file attached, into which chat; or the server's reason for refusing it.
public enum ChatAttachResult: Sendable, Equatable {
    case attached(chat: String, file: ChatFile)
    case refused(String)
}
