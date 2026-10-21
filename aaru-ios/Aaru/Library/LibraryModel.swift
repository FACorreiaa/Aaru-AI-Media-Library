import AaruAPI
import Algorithms
import Foundation
import Observation

/// The signed-in user's library: synced from `/v1/library/sync`, cached on disk, filtered here.
@MainActor
@Observable
final class LibraryModel {
    private(set) var rows: [LibraryRow] = []
    private(set) var isSyncing = false
    /// Set when the last sync failed; the cached shelf stays on screen.
    private(set) var syncProblem: String?
    private(set) var hasSynced = false
    /// Goes up whenever the shelf changes (a write here, or a sync that brought anything), so
    /// screens built from other endpoints, like Home, know to refetch.
    private(set) var revision = 0
    /// Items with a Now write in flight (APP-017), so a double tap sends one.
    var nowPending: Set<String> = []
    /// The title just removed from the library (UX-061): Library says so and points to History,
    /// where the removal undoes. Cleared when dismissed.
    var lastRemoval: String?

    /// Nothing has loaded yet and the first sync failed: show the error, never "empty" (UX-062).
    var firstSyncProblem: String? {
        hasSynced || !rows.isEmpty || isSyncing ? nil : syncProblem
    }

    @ObservationIgnored private var entries: [String: LibraryEntry] = [:]
    @ObservationIgnored private var token: String?
    @ObservationIgnored private let cache: LibraryCache
    @ObservationIgnored private var knownKeys: Set<String> = []

    init(cache: LibraryCache = LibraryCache()) {
        self.cache = cache
        if let snapshot = cache.load() {
            token = snapshot.token
            entries = snapshot.entries.keyed(by: \.id)
            publish()
        }
    }

    func entry(_ id: String) -> LibraryEntry? {
        entries[id]
    }

    func entry(forTitle titleID: String) -> LibraryEntry? {
        entries.values.first { $0.title.id == titleID }
    }

    /// Everything in progress, newest change first: what "Now" is built from.
    var inProgress: [LibraryEntry] {
        entries.values.filter { $0.status == .inProgress }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func rows(kind: MediaKind?, status: LibraryStatus?) -> [LibraryRow] {
        rows.filter { (kind == nil || $0.kind == kind) && (status == nil || $0.status == status) }
    }

    /// Whether a search hit is already in the library, by any shared provider id.
    func contains(_ hit: CatalogHit) -> Bool {
        !knownKeys.isDisjoint(with: hit.ids.keys)
    }

    /// The library's entry for a catalog hit: same type, any shared provider id.
    func entry(matching hit: CatalogHit) -> LibraryEntry? {
        let keys = hit.ids.keys
        guard contains(hit) else { return nil }
        return entries.values.first { $0.title._type == hit._type && !$0.title.ids.keys.isDisjoint(with: keys) }
    }

    /// Pulls what changed since the last sync (everything the first time).
    func sync(api: Client?) async {
        guard let api, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            switch try await api.syncLibrary(query: .init(since: token)) {
            case let .ok(response):
                let changes = try response.body.json
                for entry in changes.items {
                    entries[entry.id] = entry
                }
                for id in changes.deleted {
                    entries[id] = nil
                }
                token = changes.token
                syncProblem = nil
                hasSynced = true
                publish()
                persist()
                if !changes.items.isEmpty || !changes.deleted.isEmpty {
                    revision += 1
                }
            case let .default(_, error):
                syncProblem = (try? error.body.json.message) ?? "The library could not be updated."
            }
        } catch {
            syncProblem = rows.isEmpty
                ? "Aaru could not reach the server."
                : "Offline. Showing your library from the last sync."
        }
    }

    /// Adds a catalog hit (Search, Discover) with a starting status. Returns what went wrong, or
    /// nil when the title is in the library.
    func add(_ hit: CatalogHit, status: LibraryStatus, api: Client?) async -> String? {
        await add(MediaRef(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year), named: hit.title,
                  status: status, api: api)
    }

    /// Adds a title by reference (a list member not yet in the library, UX-072).
    func add(_ ref: MediaRef, named name: String, status: LibraryStatus, api: Client?) async -> String? {
        guard let api else { return "Aaru could not reach the server." }
        do {
            switch try await api.addLibraryItem(body: .json(.init(mediaRef: ref, status: status))) {
            case let .ok(response):
                try upsert(response.body.json)
                return nil
            case let .default(_, error):
                return (try? error.body.json.message) ?? "\(name) could not be added."
            }
        } catch {
            return "Aaru could not reach the server."
        }
    }

    /// Removes an item from the library (UX-061). The server journals it, so it undoes from
    /// Settings → Your data → History. Returns what went wrong, or nil once it is gone.
    func remove(_ id: String, api: Client?) async -> String? {
        guard let api else { return "Aaru could not reach the server." }
        let name = entries[id]?.title.title ?? "The title"
        do {
            switch try await api.deleteLibraryItem(path: .init(id: id)) {
            case .noContent:
                entries[id] = nil
                publish()
                persist()
                revision += 1
                lastRemoval = name
                return nil
            case let .default(_, error):
                return (try? error.body.json.message) ?? "\(name) was not removed."
            }
        } catch {
            return "\(name) was not removed. Aaru could not reach the server."
        }
    }

    /// A write the user just made (an add from search): shown at once, no refetch.
    func upsert(_ entry: LibraryEntry) {
        entries[entry.id] = entry
        publish()
        persist()
        revision += 1
    }

    func reset() {
        entries = [:]
        token = nil
        hasSynced = false
        syncProblem = nil
        lastRemoval = nil
        cache.clear()
        publish()
    }

    private func publish() {
        rows = entries.values.map(LibraryRow.init).sorted { $0.updatedAt > $1.updatedAt }
        knownKeys = entries.values.reduce(into: Set<String>()) { $0.formUnion($1.title.ids.keys) }
    }

    private func persist() {
        cache.save(.init(token: token, entries: Array(entries.values)))
    }
}
