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

    func rows(kind: MediaKind?, status: LibraryStatus?) -> [LibraryRow] {
        rows.filter { (kind == nil || $0.kind == kind) && (status == nil || $0.status == status) }
    }

    /// Whether a search hit is already on the shelf, by any shared provider id.
    func contains(_ hit: CatalogHit) -> Bool {
        !knownKeys.isDisjoint(with: hit.ids.keys)
    }

    /// The shelf's entry for a catalog hit: same type, any shared provider id.
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
            case let .default(_, error):
                syncProblem = (try? error.body.json.message) ?? "The library could not be updated."
            }
        } catch {
            syncProblem = rows.isEmpty
                ? "Aaru could not reach the server."
                : "Offline. Showing your library from the last sync."
        }
    }

    /// A write the user just made (an add from search): shown at once, no refetch.
    func upsert(_ entry: LibraryEntry) {
        entries[entry.id] = entry
        publish()
        persist()
    }

    func reset() {
        entries = [:]
        token = nil
        hasSynced = false
        syncProblem = nil
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
