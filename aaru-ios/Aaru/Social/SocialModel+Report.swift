import AaruAPI
import Foundation

extension SocialModel {
    /// Reports a person from their profile through the user-report route; the note starts with
    /// `profile:@<handle>` so the reviewer knows where it came from. The person is not told.
    /// Returns what went wrong, or nil when it was sent.
    func report(
        _ person: SocialUser, reason: Components.Schemas.ReportCreate.ReasonPayload, note: String?
    ) async -> String? {
        guard let api else { return "That report was not sent." }
        let composed = ["profile:@\(person.handle)", note?.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        do {
            switch try await api.reportUser(body: .json(.init(userId: person.userId, reason: reason, note: composed))) {
            case .noContent: return nil
            case let .default(_, error): return (try? error.body.json.message) ?? "That report was not sent."
            }
        } catch {
            return "That report was not sent. Aaru could not reach the server."
        }
    }
}
