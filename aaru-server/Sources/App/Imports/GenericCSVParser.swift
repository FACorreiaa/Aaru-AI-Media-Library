import AaruCore
import Foundation

/// Any other site's CSV (Simkl, Serializd, StoryGraph, a spreadsheet): columns are found by common
/// names, so a file needs only a title (and ideally a year) or an id. Rows match by id first, then
/// title + year through the catalog, exactly like the named sources.
enum GenericCSVParser {
    /// Accepted column names, compared without case, spaces, `_` or `-`.
    static let aliases: [Field: [String]] = [
        .title: ["title", "name", "seriestitle", "showtitle", "movietitle", "booktitle", "show", "movie", "book"],
        .year: [
            "year",
            "releaseyear",
            "released",
            "releasedate",
            "firstairdate",
            "airdate",
            "publicationyear",
            "originalpublicationyear",
            "yearpublished",
        ],
        .type: ["type", "mediatype", "kind", "category", "format", "titletype"],
        .imdb: ["imdb", "imdbid", "const", "tconst"],
        .tmdb: ["tmdb", "tmdbid"],
        .tvdb: ["tvdb", "tvdbid", "thetvdb"],
        .isbn: ["isbn", "isbn13", "isbn10"],
        .mal: ["mal", "malid", "myanimelistid", "animedbid", "seriesanimedbid"],
        .anilist: ["anilist", "anilistid"],
        .author: ["author", "authors"],
        .status: ["status", "state", "list", "shelf", "readstatus", "watchstatus", "exclusiveshelf"],
        .rating: ["rating", "score", "myrating", "yourrating", "userrating", "stars", "myscore"],
        .finished: [
            "watchedat",
            "watcheddate",
            "datewatched",
            "finished",
            "finishedat",
            "datefinished",
            "completedat",
            "dateread",
            "lastwatched",
        ],
    ]

    enum Field: CaseIterable {
        case title, year, type, imdb, tmdb, tvdb, isbn, mal, anilist, author, status, rating, finished
    }

    static func key(_ header: String) -> String {
        header.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func parse(_ table: CSVTable) throws -> [ImportRow] {
        var columns: [Field: String] = [:]
        for field in Field.allCases {
            columns[field] = table.headers.first { aliases[field]?.contains(key($0)) == true }
        }
        let identifying: [Field] = [.title, .imdb, .tmdb, .tvdb, .isbn, .mal, .anilist]
        guard identifying.contains(where: { columns[$0] != nil }) else {
            throw ImportFormatError(
                message: "This CSV has no column Aaru can match on. It needs a “Title” column (with a “Year” "
                    + "if possible) or an id column such as “IMDb ID”, “TMDB ID” or “ISBN”."
            )
        }
        let ratingColumn = columns[.rating]
        let scale = ratingScale(table.records.compactMap { record in ratingColumn.flatMap { record[$0] } }
            .compactMap(number))
        return table.records.enumerated().compactMap { index, record in
            func value(_ field: Field) -> String? {
                columns[field].flatMap { record[$0] }?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            let ids = ExternalIDs(
                tmdb: value(.tmdb).flatMap { Int($0) }.map(String.init),
                imdb: value(.imdb).flatMap { $0.hasPrefix("tt") ? $0 : nil },
                tvdb: value(.tvdb).flatMap { Int($0) }.map(String.init),
                isbn: value(.isbn).flatMap(ISBN.normalize),
                anilist: value(.anilist).flatMap { Int($0) }.map(String.init),
                mal: value(.mal).flatMap { Int($0) }.map(String.init)
            )
            guard let title = value(.title) ?? (ids.isEmpty ? nil : "Row \(index + 2)") else { return nil }
            let type = mediaType(value(.type), ids: ids, author: value(.author))
            return ImportRow(
                sourceKey: "row \(index + 2)",
                type: type,
                title: title,
                year: value(.year).flatMap(year),
                author: value(.author),
                ids: ids,
                status: value(.status).flatMap(status),
                rating: value(.rating).flatMap(number).map { ($0 * scale).rounded() }
                    .flatMap { (1 ... 10).contains($0) ? $0 : nil },
                finishedAt: value(.finished).flatMap(Date.catalogDay),
                lists: []
            )
        }
    }

    /// What multiplies a rating onto 1–10: stars (≤ 5) double, percentages (> 10) divide by 10.
    static func ratingScale(_ values: [Double]) -> Double {
        guard let top = values.max() else { return 1 }
        if top <= 5 {
            return 2
        }
        if top > 10 {
            return 0.1
        }
        return 1
    }

    static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// The first four-digit year in "2019", "2019-05-01" or "May 1, 2019".
    static func year(_ text: String) -> Int? {
        let digits = text.split { !$0.isNumber }.first { $0.count == 4 }
        return digits.flatMap { Int(String($0)) }.flatMap { Title.validYears.contains($0) ? $0 : nil }
    }

    static func mediaType(_ text: String?, ids: ExternalIDs, author: String?) -> MediaType {
        let kind = text.map(key) ?? ""
        if kind.contains("book") || kind.contains("novel") || ids.isbn != nil || author != nil {
            return .book
        }
        if kind.contains("movie") || kind.contains("film") {
            return .movie
        }
        if ["tv", "show", "series", "tvshow", "tvseries", "anime", "episode", "miniseries"]
            .contains(where: kind.contains)
            || ids.tvdb != nil || ids.mal != nil || ids.anilist != nil
        {
            return .show
        }
        return .movie
    }

    static func status(_ text: String) -> LibraryStatus? {
        let word = key(text)
        if ["watched", "completed", "complete", "finished", "read", "seen", "done"].contains(word) {
            return .finished
        }
        if [
            "watching",
            "reading",
            "inprogress",
            "current",
            "currentlyreading",
            "currentlywatching",
            "onhold",
            "paused",
            "rewatching",
        ].contains(word) {
            return .inProgress
        }
        if ["dropped", "abandoned", "didnotfinish", "dnf", "stopped"].contains(word) {
            return .dropped
        }
        if [
            "plantowatch",
            "plantoread",
            "planned",
            "planning",
            "watchlist",
            "wanttowatch",
            "wanttoread",
            "toread",
            "towatch",
            "wishlist",
            "backlog",
        ].contains(word) {
            return .wishlist
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

/// Picks the parser for an uploaded file when the person did not say which site it came from.
enum ImportFormatDetector {
    static func detect(_ text: String) throws -> ImportSource {
        let start = text.drop { $0.isWhitespace || $0 == "\u{FEFF}" }
        if start.hasPrefix("<") {
            guard text.contains("<myanimelist") else {
                throw ImportFormatError(
                    message: "Aaru reads MyAnimeList-format XML (exported by MyAnimeList, Kitsu and AniList). "
                        + "For other sites, export a CSV."
                )
            }
            return .malXML
        }
        if CATCalendarParser.isCalendar(text) {
            return .catICS
        }
        let headers = Set(CSVTable(String(text.prefix(4096))).headers)
        if headers.isSuperset(of: ["Const", "Title Type"]) {
            return .imdbCSV
        }
        if headers.contains("Letterboxd URI") {
            return .letterboxdCSV
        }
        if headers.isSuperset(of: ["Book Id", "Exclusive Shelf"]) {
            return .goodreadsCSV
        }
        if headers == ["Title", "Date"] {
            return .netflixCSV
        }
        return .genericCSV
    }
}
