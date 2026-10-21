import AaruAPI
import Foundation

/// The last Home load on disk, so Home opens offline like the library (APP-003). Cleared on
/// sign-out.
struct HomeCache {
    /// The newer fields are optional, so a cache written by an older build still opens.
    struct Snapshot: Codable {
        var upNext: Components.Schemas.UpNext
        var airing: [CalendarEntry]
        /// The last 7 days' numbers for the week strip (GAM-006d). A new key, so an older
        /// build's month numbers are never shown as a week.
        var weekStats: Stats?
    }

    let url: URL
    /// Discover rows (DISC-001) load on their own, so they keep their own file. Home and the
    /// Discover tab share it. The rows carry the caller's `libraryItemId`, so sign-out clears it.
    let discoverURL: URL
    /// An earlier build's Discover file in another shape; only ever removed.
    private let legacyDiscoverURL: URL

    init(fileManager: FileManager = .default) {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        url = base.appendingPathComponent("home.json")
        discoverURL = base.appendingPathComponent("discover-rows.json")
        legacyDiscoverURL = base.appendingPathComponent("discover.json")
    }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func loadDiscover() -> [DiscoverRow]? {
        guard let data = try? Data(contentsOf: discoverURL) else { return nil }
        return try? JSONDecoder().decode([DiscoverRow].self, from: data)
    }

    func saveDiscover(_ rows: [DiscoverRow]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: discoverURL, options: [.atomic, .completeFileProtection])
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: discoverURL)
        try? FileManager.default.removeItem(at: legacyDiscoverURL)
    }
}
