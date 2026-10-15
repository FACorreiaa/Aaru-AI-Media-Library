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

    var label: String {
        switch self {
        case .imdb: "IMDb"
        case .letterboxd: "Letterboxd"
        case .goodreads: "Goodreads"
        }
    }

    var hint: String {
        switch self {
        case .imdb: "Your ratings or watchlist export (CSV)."
        case .letterboxd: "diary.csv, ratings.csv, watched.csv or watchlist.csv from your export."
        case .goodreads: "goodreads_library_export.csv. Custom shelves become lists."
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
        case .catList, .catIcs: "Pogdesign CAT"
        }
    }

    var stateLabel: String {
        switch state {
        case .queued: "Waiting"
        case .running: "Matching titles…"
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
                body: .csv(HTTPBody(data))
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
