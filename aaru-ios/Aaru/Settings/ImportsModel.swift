import AaruAPI
import Foundation
import Observation
import OpenAPIRuntime

typealias ImportJob = Components.Schemas.ImportJob
typealias ImportDetail = Components.Schemas.ImportDetail
typealias ImportFileSource = Operations.CreateCSVImport.Input.Query.SourcePayload

extension ImportFileSource: @retroactive Identifiable {
    public var id: String {
        rawValue
    }

    /// What Settings offers. `csv` is reached through `auto`, which detects every format.
    static let offered: [ImportFileSource] = [.auto, .imdb, .letterboxd, .goodreads, .mal]

    var label: String {
        switch self {
        case .auto: "Any site"
        case .csv: "CSV"
        case .imdb: "IMDb"
        case .letterboxd: "Letterboxd"
        case .goodreads: "Goodreads"
        case .mal: "MyAnimeList"
        }
    }

    var hint: String {
        switch self {
        case .auto, .csv:
            "A CSV from any site (Simkl, Serializd, StoryGraph, a spreadsheet) or MAL-format XML "
                + "(MyAnimeList, Kitsu, AniList). Aaru reads the columns."
        case .imdb: "Your ratings or watchlist export (CSV)."
        case .letterboxd: "diary.csv, ratings.csv, watched.csv or watchlist.csv from your export."
        case .goodreads: "goodreads_library_export.csv. Custom shelves become lists."
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
        case .malXml: "MyAnimeList"
        case .anilist: "AniList"
        case .csv: "CSV"
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

/// APP-007: the user's imports. Upload a file, watch it get matched, approve the plan.
@MainActor
@Observable
final class ImportsModel {
    private(set) var jobs: [ImportJob] = []
    var problem: String?

    @ObservationIgnored private let api: Client?

    init(api: Client?) {
        self.api = api
    }

    func load() async {
        guard let api else { return }
        do {
            if case let .ok(response) = try await api.listImports() {
                jobs = try response.body.json.items
            }
        } catch {
            problem = "Your imports could not be loaded. Aaru could not reach the server."
        }
    }

    /// Uploads one export file. The server parses it now and matches it in the background.
    func upload(_ data: Data, filename: String, source: ImportFileSource) async -> ImportJob? {
        guard let api else { return nil }
        problem = nil
        do {
            let output = try await api.createCSVImport(
                query: .init(source: source, filename: filename),
                // `auto` is sniffed by the server; the type only says which body this is.
                body: source == .mal || data.first == UInt8(ascii: "<") ? .xml(HTTPBody(data)) : .csv(HTTPBody(data))
            )
            switch output {
            case let .accepted(response):
                let job = try response.body.json
                jobs.insert(job, at: 0)
                return job
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That file could not be imported."
            }
        } catch {
            problem = "That file could not be uploaded. Aaru could not reach the server."
        }
        return nil
    }

    /// A public AniList anime list (IMP-014). The server reads it in the background; the job's
    /// `filename` is the username.
    func importAniList(username: String) async -> ImportJob? {
        guard let api else { return nil }
        problem = nil
        do {
            switch try await api.createAniListImport(body: .json(.init(username: username))) {
            case let .accepted(response):
                let job = try response.body.json
                jobs.insert(job, at: 0)
                return job
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That AniList list could not be imported."
            }
        } catch {
            problem = "The import did not start. Aaru could not reach the server."
        }
        return nil
    }

    /// IMP-009/010: Pogdesign CAT, as a pasted show list or the exported iCal file's text.
    func importCAT(_ text: String) async -> ImportJob? {
        guard let api else { return nil }
        problem = nil
        let body = HTTPBody(text)
        let isCalendar = text.drop { $0.isWhitespace || $0 == "\u{FEFF}" }.uppercased().hasPrefix("BEGIN:VCALENDAR")
        do {
            switch try await api.createCATImport(body: isCalendar ? .textCalendar(body) : .plainText(body)) {
            case let .accepted(response):
                let job = try response.body.json
                jobs.insert(job, at: 0)
                return job
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Those shows could not be imported."
            }
        } catch {
            problem = "The import did not start. Aaru could not reach the server."
        }
        return nil
    }

    /// IMP-010: the user's CAT iCal link. The server reads it once and does not keep it.
    func importCATLink(_ url: String) async -> ImportJob? {
        guard let api else { return nil }
        problem = nil
        do {
            switch try await api.createCATFeedImport(body: .json(.init(url: url))) {
            case let .accepted(response):
                let job = try response.body.json
                jobs.insert(job, at: 0)
                return job
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That CAT link could not be imported."
            }
        } catch {
            problem = "The import did not start. Aaru could not reach the server."
        }
        return nil
    }

    /// IMP-016: a code the user approves on stremio.com. No Stremio password reaches Aaru.
    func startStremioImport() async -> Components.Schemas.StremioLink? {
        guard let api else { return nil }
        problem = nil
        do {
            switch try await api.startStremioLink() {
            case let .ok(response):
                return try response.body.json
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Stremio could not be reached. Try again in a minute."
            }
        } catch {
            problem = "Stremio could not be reached. Aaru could not reach the server."
        }
        return nil
    }

    enum StremioPoll {
        case pending
        case imported(ImportJob)
        case failed
    }

    /// Pending until the code is approved; then the server has read the library once and queued it.
    func pollStremioImport(code: String) async -> StremioPoll {
        guard let api else { return .failed }
        do {
            switch try await api.pollStremioLink(path: .init(code: code)) {
            case .noContent:
                return .pending
            case let .accepted(response):
                let job = try response.body.json
                jobs.insert(job, at: 0)
                return .imported(job)
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Your Stremio history could not be imported."
            }
        } catch {
            // A dropped connection while waiting is not the end: ask again on the next tick.
            return .pending
        }
        return .failed
    }

    /// One job without its rows, from the job list: what polling needs while a big import is
    /// matched (IMP-017). The rows are read once, when the plan is ready.
    func job(_ id: String) async -> ImportJob? {
        await load()
        return jobs.first { $0.id == id }
    }

    func detail(_ id: String) async -> ImportDetail? {
        guard let api else { return nil }
        do {
            if case let .ok(response) = try await api.getImport(path: .init(id: id)) {
                let detail = try response.body.json
                replace(detail.job)
                return detail
            }
        } catch {
            problem = "Aaru could not reach the server."
        }
        return nil
    }

    func apply(_ id: String) async -> ImportJob? {
        guard let api else { return nil }
        problem = nil
        do {
            switch try await api.applyImport(path: .init(id: id)) {
            case let .ok(response):
                let job = try response.body.json
                replace(job)
                return job
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "The import was not applied."
            }
        } catch {
            problem = "The import was not applied. Aaru could not reach the server."
        }
        return nil
    }

    func discard(_ id: String) async -> Bool {
        guard let api else { return false }
        do {
            switch try await api.deleteImport(path: .init(id: id)) {
            case .noContent:
                jobs.removeAll { $0.id == id }
                return true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "The import was not discarded."
            }
        } catch {
            problem = "Aaru could not reach the server."
        }
        return false
    }

    func reset() {
        jobs = []
        problem = nil
    }

    private func replace(_ job: ImportJob) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.insert(job, at: 0)
        }
    }
}
