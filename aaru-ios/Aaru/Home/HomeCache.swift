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

    init(fileManager: FileManager = .default) {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? fileManager.temporaryDirectory
        url = base.appendingPathComponent("home.json")
    }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
