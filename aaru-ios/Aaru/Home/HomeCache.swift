import AaruAPI
import Foundation

/// The last Home load on disk, so Home opens offline like the library (APP-003). Cleared on
/// sign-out.
struct HomeCache {
    struct Snapshot: Codable {
        var upNext: Components.Schemas.UpNext
        var airing: [CalendarEntry]
    }

    let url: URL
    /// Discover rows (DISC-001) load on their own, so they keep their own file.
    let discoverURL: URL

    init(fileManager: FileManager = .default) {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        url = base.appendingPathComponent("home.json")
        discoverURL = base.appendingPathComponent("discover.json")
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
    }
}
