import AaruCore
import Foundation

// MARK: Validation and parsing

extension GroupService {
    /// Members tagged with `@handle`, and whether `@aaru` was. A tag inside a word or an email
    /// address is not a mention.
    static func mentions(in body: String, members: [GroupMember]) -> (users: [UserID], agent: Bool) {
        mentions(in: body, users: members.map(\.user))
    }

    /// The handle-matching core, shared with the Board: the same rules over any set of people.
    static func mentions(in body: String, users: [SocialUser]) -> (users: [UserID], agent: Bool) {
        let byHandle = Dictionary(users.map { ($0.handle, $0.id) }, uniquingKeysWith: { first, _ in first })
        var users: [UserID] = []
        var agent = false
        for match in body.matches(of: /@([A-Za-z0-9_]{3,20})/) {
            let before = match.range.lowerBound == body
                .startIndex ? nil : body[body.index(before: match.range.lowerBound)]
            let after = match.range.upperBound == body.endIndex ? nil : body[match.range.upperBound]
            guard !(before.map(isHandleCharacter) ?? false), !(after.map(isHandleCharacter) ?? false) else { continue }
            let handle = match.output.1.lowercased()
            if handle == agentHandle {
                agent = true
            } else if let id = byHandle[handle], !users.contains(id) {
                users.append(id)
            }
        }
        return (users, agent)
    }

    private static func isHandleCharacter(_ character: Character) -> Bool {
        character == "_" || character == "@" || character.isLetter || character.isNumber
    }

    /// Lowercase, spaces to dashes, letters, numbers, dashes and underscores only: `Movie Night`
    /// becomes `movie-night`.
    static func channelName(_ raw: String) throws -> String {
        let words = raw.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "-" })
        let name = words.map { $0.filter { $0.isLetter || $0.isNumber || $0 == "_" } }
            .filter { !$0.isEmpty }.joined(separator: "-")
        guard !name.isEmpty, name.count <= maxChannelNameLength else {
            throw invalid("name", "Use 1–\(maxChannelNameLength) letters or numbers.")
        }
        return name
    }

    static func validName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maxNameLength else {
            throw invalid("name", "Use 1–\(maxNameLength) characters.")
        }
        return name
    }

    /// Trimmed; empty clears it.
    static func validTopic(_ raw: String?) throws -> String? {
        guard let topic = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty else { return nil }
        guard topic.count <= maxTopicLength else {
            throw invalid("topic", "Keep the topic under \(maxTopicLength) characters.")
        }
        return topic
    }

    static func validBody(_ raw: String) throws -> String {
        let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw invalid("body", "Write something first.") }
        guard body.count <= maxMessageLength else {
            throw invalid("body", "Keep messages under \(maxMessageLength) characters.")
        }
        return body
    }

    static let noSuchGroup = AppError.notFound("No such group.")
    static let noSuchMember = AppError.notFound("Not a member of this group.")
    static let noSuchInvite = AppError.notFound("No such invite.")

    static func forbidden(_ message: String) -> AppError {
        AppError(status: .forbidden, code: "forbidden", message: message)
    }

    static func invalid(_ field: String, _ message: String) -> AppError {
        AppError(status: .unprocessableContent, code: "validation_failed", message: message, details: [field: message])
    }
}
