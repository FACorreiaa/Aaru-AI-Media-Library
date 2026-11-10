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
        guard let api else { return "That report was not sent." }
        let composed = ["group-message:\(message.id)", note?.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        do {
            switch try await api.reportUser(body: .json(.init(userId: author.userId, reason: reason, note: composed))) {
            case .noContent: return nil
            case let .default(_, error): return (try? error.body.json.message) ?? "That report was not sent."
            }
        } catch {
            return "That report was not sent. Aaru could not reach the server."
        }
    }
}
