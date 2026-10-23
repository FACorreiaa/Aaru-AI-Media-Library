import AaruAPI
import Foundation

extension Client {
    /// Takes back one journaled action (`/v1/actions/{id}/undo`): an approved request or an applied
    /// import, from the toast that follows it. Returns what went wrong, or nil when it was undone.
    func takeBack(actionID: String) async -> String? {
        do {
            switch try await undoAction(path: .init(id: actionID)) {
            case .ok:
                Task { try? await WidgetSync.refresh(api: self) }
                return nil
            case let .default(_, error):
                return (try? error.body.json.message) ?? "That could not be undone."
            }
        } catch {
            return "That could not be undone. Aaru could not reach the server."
        }
    }
}
