import AaruAPI
import Foundation
import Observation
import OpenAPIRuntime

typealias ImportJob = Components.Schemas.ImportJob
typealias ImportDetail = Components.Schemas.ImportDetail
typealias ImportRow = Components.Schemas.ImportRow
/// A row matched by hand (IMP-011): the job's new counts and the row as it now stands.
typealias ResolvedImportRow = Operations.ResolveImportRow.Output.Ok.Body.JsonPayload

extension ImportRow: @retroactive Identifiable {
    public var id: Int {
        index
    }
}

typealias ImportFileSource = Operations.CreateCSVImport.Input.Query.SourcePayload

/// APP-007: the user's imports. Upload a file, watch it get matched, approve the plan.
@MainActor
@Observable
final class ImportsModel {
    private(set) var jobs: [ImportJob] = []
    /// The first load of the jobs worked, so an empty list means "No imports yet."
    private(set) var hasLoaded = false
    /// A file is being read and sent.
    private(set) var uploading = false
    /// Trakt: nil until the connection is read.
    private(set) var trakt: Components.Schemas.TraktConnection?
    private(set) var traktBusy = false
    var problem: String?

    /// The server's upload limit (`ImportService.maxUploadBytes`).
    static let maxUploadBytes = 5 * 1024 * 1024
    /// Where Trakt's sign-in sheet returns.
    static let traktReturn = "aaru://settings/trakt"

    @ObservationIgnored private let api: Client?

    init(api: Client?) {
        self.api = api
    }

    /// For previews: these jobs, nothing to fetch.
    convenience init(preview jobs: [ImportJob]) {
        self.init(api: nil)
        self.jobs = jobs
    }

    func load() async {
        guard let api else { return }
        do {
            if case let .ok(response) = try await api.listImports() {
                jobs = try response.body.json.items
                hasLoaded = true
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

    /// IMP-011: matches one unmatched row to a title the user picked in search. Before the plan is
    /// approved the pick joins it; after, that one title is written at once as its own action.
    func resolve(_ id: String, row index: Int, with hit: CatalogHit) async -> ResolvedImportRow? {
        guard let api else { return nil }
        problem = nil
        let ref = MediaRef(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year)
        do {
            switch try await api.resolveImportRow(
                path: .init(id: id, index: index), body: .json(.init(mediaRef: ref))
            ) {
            case let .ok(response):
                let resolved = try response.body.json
                replace(resolved.job)
                return resolved
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "\(hit.title) could not be matched to that row."
            }
        } catch {
            problem = "\(hit.title) was not matched. Aaru could not reach the server."
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
        hasLoaded = false
        trakt = nil
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

// MARK: Files

extension ImportsModel {
    /// Reads a picked export file and uploads it. MyAnimeList's export downloads gzipped; the
    /// server takes the XML inside.
    func upload(fileAt url: URL, source: ImportFileSource) async -> ImportJob? {
        uploading = true
        defer { uploading = false }
        problem = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard var data = try? Data(contentsOf: url) else {
            problem = "That file could not be read."
            return nil
        }
        var filename = url.lastPathComponent
        if Gunzip.isGzip(data) {
            do {
                data = try Gunzip.decompress(data, limit: Self.maxUploadBytes)
                filename = filename.hasSuffix(".gz") ? String(filename.dropLast(3)) : filename
            } catch Gunzip.Failure.tooLarge {
                problem = "That file is larger than 5 MB unpacked. Check it is the right export."
                return nil
            } catch {
                problem = "That file could not be unpacked. Upload the .xml file instead."
                return nil
            }
        }
        return await upload(data, filename: filename, source: source)
    }

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

// MARK: Trakt (IMP-002/003)

extension ImportsModel {
    func loadTrakt() async {
        guard let api else { return }
        if case let .ok(response) = try? await api.getTraktConnection() {
            trakt = try? response.body.json
        }
    }

    /// Trakt's sign-in page for this user. The server holds the PKCE verifier.
    func traktAuthorizeURL() async -> URL? {
        guard let api else { return nil }
        traktBusy = true
        defer { traktBusy = false }
        do {
            if case let .ok(response) = try await api.connectTrakt(body: .json(.init(returnTo: Self.traktReturn))),
               let page = try URL(string: response.body.json.authorizeUrl)
            {
                return page
            }
            problem = "Trakt is not available right now. Try again later."
        } catch {
            problem = "Trakt could not be reached. Aaru could not reach the server."
        }
        return nil
    }

    /// Trakt's sign-in sheet came back to `aaru://…?trakt=`.
    func finishTrakt(_ callback: URL) async {
        let result = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "trakt" }?.value
        switch result {
        case "connected": await loadTrakt()
        case "denied": break
        default:
            problem = "Trakt could not finish connecting. Free Trakt accounts can connect two apps; "
                + "disconnect one on trakt.tv, or try again."
        }
    }

    func startTraktImport() async -> ImportJob? {
        guard let api else { return nil }
        traktBusy = true
        problem = nil
        defer { traktBusy = false }
        do {
            switch try await api.createTraktImport() {
            case let .accepted(response):
                let job = try response.body.json
                jobs.insert(job, at: 0)
                return job
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That Trakt import could not be started."
            }
        } catch {
            problem = "The import did not start. Aaru could not reach the server."
        }
        return nil
    }

    func disconnectTrakt() async {
        guard let api else { return }
        traktBusy = true
        problem = nil
        defer { traktBusy = false }
        do {
            switch try await api.disconnectTrakt() {
            case .noContent:
                trakt = .init(connected: false)
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Trakt was not disconnected. Try again."
            }
        } catch {
            problem = "Trakt was not disconnected. Aaru could not reach the server."
        }
    }
}
