import AaruAPI
import Foundation
import Observation

typealias ListSummary = Components.Schemas.ListSummary
typealias ListDetail = Components.Schemas.ListDetail
typealias MediaRef = Components.Schemas.MediaRef

/// APP-006: the user's lists. Membership rows on the server; titles need not be in the library.
@MainActor
@Observable
final class ListsModel {
    private(set) var lists: [ListSummary] = []
    private(set) var hasLoaded = false
    var problem: String?

    @ObservationIgnored private let api: Client?

    init(api: Client?) {
        self.api = api
    }

    func load() async {
        guard let api else { return }
        do {
            switch try await api.listLists() {
            case let .ok(response):
                lists = try response.body.json.items
                hasLoaded = true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Your lists could not be loaded."
            }
        } catch {
            problem = "Aaru could not reach the server."
        }
    }

    @discardableResult
    func create(named name: String) async -> ListDetail? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, !name.isEmpty else { return nil }
        return await write("The list could not be created.") {
            switch try await api.createList(body: .json(.init(name: name))) {
            case let .ok(response): try response.body.json
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    func rename(_ id: String, to name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api, !name.isEmpty else { return }
        await write("The list could not be renamed.") {
            switch try await api.renameList(path: .init(id: id), body: .json(.init(name: name))) {
            case let .ok(response): try response.body.json
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    func delete(_ id: String) async {
        guard let api else { return }
        let before = lists
        lists.removeAll { $0.id == id }
        do {
            switch try await api.deleteList(path: .init(id: id)) {
            case .noContent: return
            case let .default(_, error):
                lists = before
                problem = (try? error.body.json.message) ?? "The list could not be deleted."
            }
        } catch {
            lists = before
            problem = "The list could not be deleted. Aaru could not reach the server."
        }
    }

    /// Adds a title to a list and returns the list. Adding one that is already there changes nothing.
    @discardableResult
    func add(_ ref: MediaRef, to id: String) async -> ListDetail? {
        guard let api else { return nil }
        return await write("The title could not be added to the list.") {
            switch try await api.addListItem(path: .init(id: id), body: .json(.init(mediaRef: ref))) {
            case let .ok(response): try response.body.json
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    func detail(_ id: String) async -> ListDetail? {
        guard let api else { return nil }
        return await write("The list could not be loaded.") {
            switch try await api.getList(path: .init(id: id)) {
            case let .ok(response): try response.body.json
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    func remove(titleID: String, from id: String) async -> ListDetail? {
        guard let api else { return nil }
        return await write("The title could not be removed.") {
            switch try await api.removeListItem(path: .init(id: id, titleId: titleID)) {
            case let .ok(response): try response.body.json
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    func reorder(_ id: String, titleIDs: [String]) async -> ListDetail? {
        guard let api else { return nil }
        return await write("The new order was not saved.") {
            switch try await api.reorderList(path: .init(id: id), body: .json(.init(titleIds: titleIDs))) {
            case let .ok(response): try response.body.json
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    func reset() {
        lists = []
        hasLoaded = false
        problem = nil
    }

    // MARK: Helpers

    private struct Failure: Error {
        let message: String?
        init(_ message: String?) {
            self.message = message
        }
    }

    /// Runs a write that answers with a list, folds that list into `lists`, and turns any failure
    /// into one visible message.
    @discardableResult
    private func write(_ fallback: String, _ call: () async throws -> ListDetail) async -> ListDetail? {
        problem = nil
        do {
            let detail = try await call()
            absorb(detail)
            return detail
        } catch let failure as Failure {
            problem = failure.message ?? fallback
        } catch {
            problem = "\(fallback) Aaru could not reach the server."
        }
        return nil
    }

    private func absorb(_ detail: ListDetail) {
        let summary = ListSummary(
            id: detail.id, name: detail.name, itemCount: detail.titles.count,
            createdAt: detail.createdAt, updatedAt: detail.updatedAt
        )
        if let index = lists.firstIndex(where: { $0.id == detail.id }) {
            lists[index] = summary
        } else {
            lists.insert(summary, at: 0)
        }
    }
}
