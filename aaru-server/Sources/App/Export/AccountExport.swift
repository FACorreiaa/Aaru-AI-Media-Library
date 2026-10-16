import AaruCore
import Foundation

/// Everything Aaru holds for one user, gathered for `GET /v1/me/export`. Reads only: the library
/// through sync (every item), watched episodes per show, lists with their titles, shelves.
struct AccountExport: Sendable {
    var entries: [LibraryEntry]
    var watched: [LibraryItemID: [EpisodeKey]]
    var lists: [(list: AaruList, titles: [Title])]
    var shelves: [Shelf]

    static func gather(userID: UserID, stores: Stores, services: Services) async throws -> AccountExport {
        let entries = try await services.library.sync(userID: userID, token: nil).entries
            .sorted { $0.item.addedAt < $1.item.addedAt }
        var watched: [LibraryItemID: [EpisodeKey]] = [:]
        for entry in entries where entry.title.type == .show {
            let keys = try await stores.library.watched(itemID: entry.item.id)
            if !keys.isEmpty {
                watched[entry.item.id] = keys.sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
            }
        }
        var lists: [(AaruList, [Title])] = []
        for list in try await services.lists.lists(userID: userID) {
            try await lists.append((list, stores.titles.titles(ids: list.titleIDs)))
        }
        let shelves = try await services.shelves.shelves(userID: userID)
        return AccountExport(entries: entries, watched: watched, lists: lists, shelves: shelves)
    }

    // MARK: CSV

    /// The columns Aaru's own "Any site" import reads (`GenericCSVParser`), so an export re-imports.
    static let csvHeader = [
        "Title", "Year", "Type", "Status", "Rating", "Owned", "Finished", "Added", "IMDb ID", "TMDB ID",
        "TVDB ID", "MAL ID", "AniList ID", "ISBN", "Watched Episodes", "Notes",
    ]

    var csv: String {
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        let rows = entries.map { entry -> [String] in
            let title = entry.title
            let ids = title.ids
            return [
                title.title, title.year.map(String.init) ?? "", title.isAnime ? "anime" : title.type.rawValue,
                Self.statusWord(entry.item.status), entry.item.rating.map { Self.number($0.value) } ?? "",
                entry.item.isOwned ? "yes" : "", entry.item.finishedAt.map(day.string) ?? "",
                day.string(from: entry.item.addedAt), ids.imdb ?? "", ids.tmdb ?? "", ids.tvdb ?? "",
                ids.mal ?? "", ids.anilist ?? "", ids.isbn ?? "",
                (watched[entry.item.id] ?? []).map { String(format: "S%02dE%02d", $0.season, $0.episode) }
                    .joined(separator: " "),
                entry.item.notes ?? "",
            ]
        }
        return ([Self.csvHeader] + rows).map { $0.map(Self.field).joined(separator: ",") }.joined(separator: "\r\n")
            + "\r\n"
    }

    /// Words the generic importer maps back to the same status.
    static func statusWord(_ status: LibraryStatus) -> String {
        switch status {
        case .wishlist: "Plan to watch"
        case .inProgress: "Watching"
        case .finished: "Completed"
        case .dropped: "Dropped"
        }
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// RFC 4180: quote fields with a comma, quote or line break; double inner quotes. A leading
    /// `=`, `+`, `-` or `@` is prefixed with `'` so a spreadsheet never runs it as a formula.
    static func field(_ value: String) -> String {
        var text = value
        if let first = text.first, "=+-@".contains(first) {
            text = "'" + text
        }
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
