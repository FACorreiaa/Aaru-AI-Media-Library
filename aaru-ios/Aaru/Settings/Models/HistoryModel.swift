import AaruAPI
import Foundation
import Observation

typealias JournalAction = Components.Schemas.Action

extension JournalAction {
    /// Who made it, in the words History shows: you, an import, a connected app, or Aaru.
    var byline: String {
        if let agentName {
            return agentName
        }
        if kind == "import" {
            return "An import"
        }
        switch actor {
        case .user: return "You"
        case .agent: return "Aaru"
        case .externalAgent: return "A connection"
        }
    }

    /// An undo can itself be undone? No: the server answers 409. Undone actions stay listed.
    var canUndo: Bool {
        undoneAt == nil && kind != "undo"
    }

    var symbol: String {
        switch kind {
        case "add": "plus.circle"
        case "remove": "minus.circle"
        case "update", "tv": "pencil.circle"
        case "list": "list.bullet.circle"
        case "import": "tray.and.arrow.down"
        case "plan": "sparkles"
        case "undo": "arrow.uturn.backward.circle"
        default: "circle"
        }
    }
}

/// Settings → Your data → History (UX-060): the action journal, newest first, with Undo
/// (GET /v1/actions, POST /v1/actions/{id}/undo). Every write a tap, an import or a
/// connection made lands here, so every "undo it from your history" line has a place to go.
@MainActor
@Observable
final class HistoryModel {
    private(set) var actions: [JournalAction] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    /// The first load failed: History shows the error state, not "Nothing yet".
    private(set) var loadFailure: String?
    /// The action being undone, so its row shows progress.
    private(set) var undoing: String?
    var problem: String?

    @ObservationIgnored private let api: Client?
    /// The server's page cap (`Limit`).
    private static let page = 200

    init(api: Client?) {
        self.api = api
    }

    /// For previews: these actions, nothing to fetch.
    convenience init(preview actions: [JournalAction]) {
        self.init(api: nil)
        self.actions = actions
        hasLoaded = true
    }

    func load() async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            switch try await api.listActions(query: .init(limit: Self.page)) {
            case let .ok(response):
                actions = try response.body.json.items
                hasLoaded = true
                loadFailure = nil
            case let .default(_, error):
                fail((try? error.body.json.message) ?? "Your history could not be loaded.")
            }
        } catch {
            fail("Your history could not be loaded. Aaru could not reach the server.")
        }
    }

    /// Applies the action's inverse. The undo is journaled too, so the list reloads to show it.
    /// True when it worked, so the caller can refresh the library.
    func undo(_ action: JournalAction) async -> Bool {
        guard let api, action.canUndo else { return false }
        undoing = action.id
        problem = nil
        defer { undoing = nil }
        do {
            switch try await api.undoAction(path: .init(id: action.id)) {
            case .ok:
                await load()
                return true
            case let .default(status, error):
                problem = status == 409
                    ? "That was already undone."
                    : (try? error.body.json.message) ?? "That was not undone."
            }
        } catch {
            problem = "That was not undone. Aaru could not reach the server."
        }
        return false
    }

    func reset() {
        actions = []
        hasLoaded = false
        loadFailure = nil
        problem = nil
    }

    private func fail(_ message: String) {
        if hasLoaded {
            problem = message
        } else {
            loadFailure = message
        }
    }
}
