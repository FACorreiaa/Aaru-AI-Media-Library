import AaruAPI
import Foundation

/// The import sources Settings → Import lists, in `CLAUDE.md`'s order (UX-026).
extension ImportFileSource: @retroactive Identifiable {
    public var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .auto: "Any other CSV"
        case .csv: "CSV"
        case .imdb: "IMDb"
        case .letterboxd: "Letterboxd"
        case .netflix: "Netflix"
        case .tvtime: "TV Time"
        case .goodreads: "Goodreads"
        case .mal: "MyAnimeList"
        }
    }

    var hint: String {
        switch self {
        case .auto, .csv:
            "A CSV from any other site, or a spreadsheet. Aaru reads the columns."
        case .imdb: "Your ratings or watchlist export (CSV)."
        case .letterboxd: "diary.csv, ratings.csv, watched.csv or watchlist.csv from your export."
        case .netflix: "Account → Profile → Viewing activity → Download all. One profile per file."
        case .tvtime:
            "Unzip your TV Time export, then upload one CSV at a time: tvtime-series-episodes.csv, "
                + "tvtime-series.csv and tvtime-movies.csv, or from a GDPR export tracking-prod-records-v2.csv "
                + "and tracking-prod-records.csv."
        case .goodreads:
            "On Goodreads: My Books → Import and export → Export Library, then upload the CSV. "
                + "Goodreads closed its API, so there is no connect option. Custom shelves become lists."
        case .mal: "On MyAnimeList: Profile → Export → Anime list. The .xml or .xml.gz file."
        }
    }
}

extension ImportJob {
    var sourceLabel: String {
        switch source {
        case .imdbCsv: "IMDb"
        case .letterboxdCsv: "Letterboxd"
        case .goodreadsCsv: "Goodreads"
        case .trakt: "Trakt"
        case .stremio: "Stremio"
        case .catList, .catIcs: "Pogdesign CAT"
        case .netflixCsv: "Netflix"
        case .tvtimeCsv: "TV Time"
        case .malXml: "MyAnimeList"
        case .anilist: "AniList"
        case .csv: "CSV"
        case .capture: "Capture"
        }
    }

    var stateLabel: String {
        switch state {
        case .queued: errorSummary == nil ? "In line" : "Paused, retrying soon"
        case .running: rowsTotal > 0
            ? "Matching titles… \(min(100, rowsMatched * 100 / rowsTotal))%"
            : "Matching titles…"
        case .planned: "Ready to review"
        case .succeeded: "Imported"
        case .partial: "Imported, \(stats.unmatched) unmatched"
        case .failed: "Failed"
        }
    }

    /// Still changing on the server: the screen polls until it is not.
    var isWorking: Bool {
        state == .queued || state == .running
    }
}

/// One row of Import's "Bring your history", in `CLAUDE.md`'s import order (UX-026). Trakt has
/// its own section above; "Any other CSV" is last and only fills gaps.
enum HistorySource: Hashable, Identifiable {
    case stremio
    case file(ImportFileSource)
    case cat
    case aniList

    static let ordered: [HistorySource] = [
        .stremio, .file(.imdb), .file(.letterboxd), .file(.goodreads), .cat, .file(.netflix), .file(.tvtime),
        .file(.mal), .aniList, .file(.auto),
    ]

    var id: String {
        switch self {
        case .stremio: "stremio"
        case let .file(source): source.rawValue
        case .cat: "cat"
        case .aniList: "anilist"
        }
    }

    var title: String {
        switch self {
        case .stremio: "Stremio history"
        case let .file(source): source.label
        case .cat: "Pogdesign CAT"
        case .aniList: "AniList"
        }
    }

    var hint: String {
        switch self {
        case .stremio: "What you watched before, approved on stremio.com."
        case let .file(source): source.hint
        case .cat: "Your iCal link or file, or a list of shows."
        case .aniList: "Your public anime list, by username."
        }
    }
}

extension ImportsModel {
    /// CAT's exported iCal file, read as text.
    func importCATFile(at url: URL) async -> ImportJob? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url), data.count <= Self.maxUploadBytes,
              let text = String(bytes: data, encoding: .utf8)
        else {
            problem = "That file could not be read, or is larger than 5 MB."
            return nil
        }
        return await importCAT(text)
    }
}
