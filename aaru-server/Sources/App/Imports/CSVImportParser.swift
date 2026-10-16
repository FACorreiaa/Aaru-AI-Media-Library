import AaruCore
import Foundation

/// IMP-006/007/008: the known export layouts. Each parser checks its columns first, so a file
/// uploaded as the wrong source fails with a readable message instead of importing nonsense.
enum CSVImportParser {
    static func parse(_ text: String, source: ImportSource, filename: String?) throws -> [ImportRow] {
        let table = CSVTable(text)
        switch source {
        case .imdbCSV: return try imdb(table)
        case .letterboxdCSV: return try letterboxd(table, filename: filename)
        case .goodreadsCSV: return try goodreads(table)
        case .trakt, .catList, .catICS, .malXML, .anilist:
            throw ImportFormatError(message: "\(source.rawValue) is not a CSV import.")
        }
    }

    private static func require(_ columns: [String], in table: CSVTable, source: String) throws {
        let missing = columns.filter { !table.headers.contains($0) }
        guard missing.isEmpty else {
            throw ImportFormatError(
                message: "This does not look like a \(source) export: it has no "
                    + missing.map { "“\($0)”" }.joined(separator: ", ") + " column."
            )
        }
    }

    // MARK: IMDb (ratings or watchlist export)

    /// `tconst` is a hard id, so these rows match exactly. Episode rows are not imported: they
    /// are listed as unmatched with a reason, so the person adds the show instead (decided for
    /// IMP-006). A `Position` column means the watchlist export.
    static func imdb(_ table: CSVTable) throws -> [ImportRow] {
        try require(["Const", "Title", "Title Type"], in: table, source: "IMDb")
        let isWatchlist = table.headers.contains("Position")
        return table.records.compactMap { record in
            guard let const = record["Const"], const.hasPrefix("tt"), let title = record["Title"] else { return nil }
            let kind = record["Title Type"]?.lowercased() ?? ""
            let type: MediaType = ["tvseries", "tv series", "tvminiseries", "tv mini series"].contains(kind)
                ? .show : .movie
            let rating = record["Your Rating"].flatMap(Double.init).flatMap { (1 ... 10).contains($0) ? $0 : nil }
            var row = ImportRow(
                sourceKey: const, type: type, title: title, year: record["Year"].flatMap { Int($0) },
                ids: ExternalIDs(imdb: const),
                status: isWatchlist ? .wishlist : .finished,
                rating: rating,
                finishedAt: isWatchlist ? nil : record["Date Rated"].flatMap(day),
                lists: []
            )
            if kind.contains("episode") {
                row.unsupported = "An episode row. Episodes are not imported; add the show instead."
            }
            return row
        }
    }

    // MARK: Letterboxd (diary, ratings, watched or watchlist export)

    /// No external id: title + year through a catalog search, never guessed (IMP-007). The 0.5–5
    /// star scale doubles onto 1–10. The watchlist export has the same columns as the watched
    /// one, so its file name decides.
    static func letterboxd(_ table: CSVTable, filename: String?) throws -> [ImportRow] {
        try require(["Name", "Year"], in: table, source: "Letterboxd")
        let isWatchlist = filename?.lowercased().contains("watchlist") == true
        return table.records.compactMap { record in
            guard let name = record["Name"], !name.isEmpty else { return nil }
            let stars = record["Rating"].flatMap(Double.init)
            return ImportRow(
                sourceKey: record["Letterboxd URI"], type: .movie, title: name,
                year: record["Year"].flatMap { Int($0) }, ids: ExternalIDs(),
                status: isWatchlist ? .wishlist : .finished,
                rating: stars.map { $0 * 2 },
                finishedAt: (record["Watched Date"] ?? record["Date"]).flatMap(day).flatMap { isWatchlist ? nil : $0 },
                lists: []
            )
        }
    }

    // MARK: Goodreads

    /// Exclusive Shelf → status; custom shelves → lists; ISBNs arrive as `="0441172717"`.
    static func goodreads(_ table: CSVTable) throws -> [ImportRow] {
        try require(["Title", "Author", "Exclusive Shelf"], in: table, source: "Goodreads")
        let exclusive: Set = ["to-read", "currently-reading", "read"]
        return table.records.compactMap { record in
            guard let title = record["Title"], !title.isEmpty else { return nil }
            let isbn = [record["ISBN13"], record["ISBN"]].compactMap { $0.flatMap(cleanISBN) }.first
            let shelf = record["Exclusive Shelf"] ?? ""
            let status: LibraryStatus? = switch shelf {
            case "to-read": .wishlist
            case "currently-reading": .inProgress
            case "read": .finished
            default: nil
            }
            let stars = record["My Rating"].flatMap(Double.init) ?? 0
            let lists = (record["Bookshelves"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !exclusive.contains($0) }
            return ImportRow(
                sourceKey: record["Book Id"], type: .book, title: title,
                year: (record["Original Publication Year"] ?? record["Year Published"]).flatMap { Int($0) },
                author: record["Author"],
                ids: ExternalIDs(isbn: isbn.flatMap(ISBN.normalize)),
                status: status,
                rating: stars > 0 ? stars * 2 : nil,
                finishedAt: record["Date Read"].flatMap(day),
                lists: lists
            )
        }
    }

    /// Goodreads wraps ISBNs as `="0441172717"` and leaves `=""` when there is none.
    static func cleanISBN(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber || $0 == "X" || $0 == "x" }
        return digits.isEmpty ? nil : digits
    }

    /// `2024-03-01` or `2024/03/01`, at noon UTC so no time zone moves it to another day.
    static func day(_ raw: String) -> Date? {
        let parts = raw.split(whereSeparator: { $0 == "-" || $0 == "/" }).compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 1800 else { return nil }
        var components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)
    }
}
