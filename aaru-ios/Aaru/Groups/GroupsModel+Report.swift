import AaruAPI
import Foundation

extension GroupsModel {
    /// Reports a group message through the user-report route; the note starts with
    /// `group-message:<id>` so the reviewer knows which one, as the web does and as a Board post is
    /// reported. The author is not told. Returns what went wrong, or nil when it was sent.
    func report(
        _ message: GroupMessage, by author: SocialUser,
        reason: Components.Schemas.ReportCreate.ReasonPayload, note: String?
    ) async -> String? {
        guard let api else { return String(localized: "That report was not sent.") }
        let composed = ["group-message:\(message.id)", note?.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        do {
            switch try await api.reportUser(body: .json(.init(userId: author.userId, reason: reason, note: composed))) {
            case .noContent: return nil
            case let .default(_, error): return (try? error.body.json.message) ??
                String(localized: "That report was not sent.")
            }
        } catch {
            return String(localized: "That report was not sent. Aaru could not reach the server.")
        }
    }

    /// Blocks a member from one of their group messages. Both of you stay in the group; the
    /// channel then shows their messages collapsed. They are not told. Returns what went wrong,
    /// or nil when they were blocked.
    func block(_ person: SocialUser) async -> String? {
        guard let api else { return String(localized: "That person was not blocked.") }
        do {
            switch try await api.blockUser(path: .init(userId: person.userId)) {
            case .noContent: return nil
            case let .default(_, error): return (try? error.body.json.message) ??
                String(localized: "That person was not blocked.")
            }
        } catch {
            return String(localized: "That person was not blocked. Aaru could not reach the server.")
        }
    }
}
