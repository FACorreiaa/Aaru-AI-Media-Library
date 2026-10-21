import AaruAPI
import Foundation
import Observation

typealias ChannelItem = Components.Schemas.ChannelItem

/// GRP-008: a shared-list channel's titles (the `shelf` kind, "List" in the UI). Any member adds
/// or removes one; "Add to my library" is the same journaled add as anywhere else, for this user
/// only.
@MainActor
@Observable
final class ShelfModel {
    private(set) var items: [ChannelItem] = []
    private(set) var hasLoaded = false
    private(set) var adding: Set<String> = []
    /// Why the first load failed; nil once anything has loaded (UX-063).
    private(set) var loadProblem: String?
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored let groupID: String
    @ObservationIgnored let channelID: String

    init(api: Client?, groupID: String, channelID: String) {
        self.api = api
        self.groupID = groupID
        self.channelID = channelID
    }

    func load() async {
        guard let api else { return }
        do {
            switch try await api.listChannelItems(path: .init(groupId: groupID, channelId: channelID)) {
            case let .ok(response):
                items = try response.body.json.items
                hasLoaded = true
                loadProblem = nil
            case let .default(_, error):
                loadFailed((try? error.body.json.message) ?? "This list could not be loaded.")
            }
        } catch {
            loadFailed("This list could not be loaded. Aaru could not reach the server.")
        }
    }

    private func loadFailed(_ message: String) {
        if hasLoaded {
            problem = message
        } else {
            loadProblem = message
        }
    }

    func add(_ title: Components.Schemas.MediaRef) async -> Bool {
        guard let api else { return false }
        problem = nil
        do {
            switch try await api.addChannelItem(
                path: .init(groupId: groupID, channelId: channelID), body: .json(.init(title: title))
            ) {
            case let .ok(response):
                items = try response.body.json.items
                return true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That title was not added."
            }
        } catch {
            problem = "That title was not added. Aaru could not reach the server."
        }
        return false
    }

    func remove(_ item: ChannelItem) async {
        guard let api else { return }
        problem = nil
        do {
            switch try await api.removeChannelItem(
                path: .init(groupId: groupID, channelId: channelID, titleId: item.title.id)
            ) {
            case .noContent: items.removeAll { $0.title.id == item.title.id }
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That title was not removed."
            }
        } catch {
            problem = "That title was not removed. Aaru could not reach the server."
        }
    }

    /// The user's own wishlist add; the list then shows their status.
    func addToMyLibrary(_ item: ChannelItem) async {
        guard let api, !adding.contains(item.title.id) else { return }
        adding.insert(item.title.id)
        defer { adding.remove(item.title.id) }
        problem = nil
        do {
            switch try await api.addLibraryItem(body: .json(.init(mediaRef: item.title.mediaRef, status: .wishlist))) {
            case .ok: await load()
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "\(item.title.title) was not added."
            }
        } catch {
            problem = "\(item.title.title) was not added. Aaru could not reach the server."
        }
    }

    func apply(_ event: RealtimeEvent) async {
        if event._type == .ready || (event._type == .shelf_updated && event.channelId == channelID) {
            await load()
        }
    }
}
