import AaruCore
import Foundation

/// IMP-018: Netflix's viewing activity (Account → Profile → Viewing activity → Download all),
/// `NetflixViewingHistory.csv`. Two columns, `Title` and `Date`, one profile per file. A title is
/// `Show: Season 1: Episode name` (or `Limited Series`, `Part 2`, `Stranger Things 4`, …) or a
/// film's name. No ids and no release year, so rows are `nameOnly`: they match only when exactly
/// one catalog entry has the name and came out by the year it was first watched. Episodes come
/// by name and are numbered once the show's episode list is known.
enum NetflixCSVParser {
    static func parse(_ table: CSVTable) throws -> [ImportRow] {
        if table.headers.contains("Profile Name") {
            throw ImportFormatError(
                message: "This is Netflix's full account download, with every profile in it. "
                    + "Use Account → Profile → Viewing activity → Download all instead, one profile per file."
            )
        }
        let missing = ["Title", "Date"].filter { !table.headers.contains($0) }
        guard missing.isEmpty else {
            throw ImportFormatError(
                message: "This does not look like a Netflix viewing activity file: it has no "
                    + missing.map { "“\($0)”" }.joined(separator: ", ") + " column."
            )
        }
        let order = DateOrder.of(table.records.compactMap { $0["Date"] })
        var index: [String: Int] = [:]
        var rows: [ImportRow] = []
        var firstYears: [Int?] = []
        for record in table.records {
            guard let raw = record["Title"], !raw.isEmpty else { continue }
            let watched = record["Date"].flatMap { day($0, order: order) }
            let entry = entry(raw)
            let key = "\(entry.type.rawValue):\(MatchKey.normalize(entry.title))"
            guard !MatchKey.normalize(entry.title).isEmpty else { continue }
            let slot: Int
            if let seen = index[key] {
                slot = seen
            } else {
                slot = rows.count
                index[key] = slot
                rows.append(ImportRow(
                    sourceKey: "netflix:\(entry.title)", type: entry.type, title: entry.title, ids: ExternalIDs(),
                    status: entry.type == .movie ? .finished : .inProgress, lists: [], nameOnly: true
                ))
                firstYears.append(nil)
            }
            if let episode = entry.episode, !(rows[slot].namedEpisodes ?? []).contains(episode) {
                rows[slot].namedEpisodes = (rows[slot].namedEpisodes ?? []) + [episode]
            }
            if let watched {
                let year = Calendar.utc.component(.year, from: watched)
                firstYears[slot] = min(firstYears[slot] ?? year, year)
                if entry.type == .movie, rows[slot].finishedAt.map({ watched > $0 }) ?? true {
                    rows[slot].finishedAt = watched
                }
            }
        }
        for slot in rows.indices {
            rows[slot].notAfter = firstYears[slot]
        }
        return rows
    }

    // MARK: Titles

    struct Entry: Equatable {
        var type: MediaType
        var title: String
        var episode: NamedEpisode?
    }

    /// `Show: Season 2: Name` → the show, season 2, episode "Name". The first segment that reads as
    /// a season splits it; a title with none is a film (`Mission: Impossible - Fallout`).
    static func entry(_ raw: String) -> Entry {
        let parts = raw.components(separatedBy: ": ").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 3 {
            for split in 1 ..< parts.count - 1 {
                let show = parts[..<split].joined(separator: ": ")
                if let season = season(parts[split], show: show) {
                    let name = parts[(split + 1)...].joined(separator: ": ")
                    return Entry(type: .show, title: show, episode: NamedEpisode(season: season, name: name))
                }
            }
        }
        return Entry(type: .movie, title: raw.trimmingCharacters(in: .whitespaces))
    }

    /// Season words in the languages Netflix writes its export in.
    private static let seasonWords: Set<String> = [
        "season", "series", "part", "volume", "vol", "book", "chapter", "collection",
        "temporada", "saison", "staffel", "stagione", "seizoen", "sezon", "säsong", "sæson", "sesong",
    ]
    private static let limitedSeries: Set<String> = [
        "limited series", "miniseries", "mini series", "miniserie", "minisérie", "série limitée",
    ]

    /// `Season 2` → 2, `Limited Series` → 1, `Stranger Things 4` (the show's own name) → 4.
    static func season(_ segment: String, show: String) -> Int? {
        let lowered = segment.lowercased()
        if limitedSeries.contains(lowered) {
            return 1
        }
        let words = lowered.replacingOccurrences(of: ".", with: " ").split(separator: " ").map(String.init)
        if words.count == 2, seasonWords.contains(words[0]), let number = Int(words[1]), (0 ... 200).contains(number) {
            return number
        }
        if let match = segment.wholeMatch(of: /(.+)\s+(\d{1,2})/), let number = Int(match.2),
           MatchKey.normalize(String(match.1)) == MatchKey.normalize(show)
        {
            return number
        }
        return nil
    }

    // MARK: Dates

    /// The account's locale decides the layout. A file is read one way throughout: day first when
    /// any date's first number passes 12, else month first (Netflix's US layout).
    enum DateOrder {
        case monthFirst, dayFirst

        static func of(_ dates: [String]) -> DateOrder {
            for raw in dates {
                let parts = numbers(raw)
                if parts.count == 3, parts[0] <= 31, parts[0] > 12 {
                    return .dayFirst
                }
            }
            return .monthFirst
        }
    }

    /// `1/23/24`, `23/01/2024`, `23.01.2024` or `2024-01-23`, at noon UTC.
    static func day(_ raw: String, order: DateOrder) -> Date? {
        let parts = numbers(raw)
        guard parts.count == 3 else { return nil }
        let isoOrder = parts[0] > 31
        let year = isoOrder ? parts[0] : parts[2] < 100 ? 2000 + parts[2] : parts[2]
        let (month, day) = isoOrder ? (parts[1], parts[2])
            : order == .monthFirst ? (parts[0], parts[1]) : (parts[1], parts[0])
        guard (1990 ... 2100).contains(year), (1 ... 12).contains(month), (1 ... 31).contains(day) else { return nil }
        let components = DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: year,
            month: month,
            day: day,
            hour: 12
        )
        return Calendar.utc.date(from: components)
    }

    private static func numbers(_ raw: String) -> [Int] {
        raw.split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." }).compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
    }
}

private extension Calendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}
