import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func listImports(_: Operations.ListImports.Input) async throws -> Operations.ListImports.Output {
        try await .ok(.init(body: .json(.init(
            items: services.imports.jobs(userID: currentUser()).map(Components.Schemas.ImportJob.init)
        ))))
    }

    func createCSVImport(_ input: Operations.CreateCSVImport.Input) async throws -> Operations.CreateCSVImport
        .Output
    {
        let body: HTTPBody
        switch input.body {
        case let .csv(file), let .xml(file): body = file
        case let .binary(file): return try await createListenFileImport(file, query: input.query)
        }
        let text = try await Self.text(body)
        let source = try Self.fileSource(input.query.source, text: text)
        let job = try await services.imports.createCSVImport(
            userID: currentUser(), source: source, filename: input.query.filename, text: text
        )
        return .accepted(.init(body: .json(.init(job))))
    }

    /// A text export's source: the one asked for, or what `auto` detects.
    private static func fileSource(_ asked: Operations.CreateCSVImport.Input.Query.SourcePayload, text: String) throws
        -> ImportSource
    {
        switch asked {
        case .imdb: return .imdbCSV
        case .letterboxd: return .letterboxdCSV
        case .netflix: return .netflixCSV
        case .tvtime: return .tvTimeCSV
        case .goodreads: return .goodreadsCSV
        case .mal: return .malXML
        case .csv: return .genericCSV
        case .spotify, .youtube:
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Send Spotify and YouTube history as the JSON file itself, not as a CSV.",
                details: ["file": "Send the JSON file itself."]
            )
        case .auto:
            do {
                return try ImportFormatDetector.detect(text)
            } catch let error as ImportFormatError {
                throw AppError(
                    status: .unprocessableContent, code: "validation_failed", message: error.message,
                    details: ["file": error.message]
                )
            }
        }
    }

    /// MUS-004: a Spotify or YouTube listening history file. Bigger than an export, so its own limit.
    private func createListenFileImport(_ body: HTTPBody, query: Operations.CreateCSVImport.Input.Query) async throws
        -> Operations.CreateCSVImport.Output
    {
        let source: ImportSource?
        switch query.source {
        case .spotify: source = .spotifyJSON
        case .youtube: source = .youTubeTakeout
        case .auto: source = nil
        default:
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Only Spotify and YouTube history are JSON. Send other exports as CSV or XML.",
                details: ["file": "Only Spotify and YouTube history are JSON."]
            )
        }
        let limit = ImportService.maxListenUploadBytes
        let tooLarge = AppError(
            status: .contentTooLarge, code: "file_too_large",
            message: "That file is larger than 24 MB, the most Aaru reads at once. Spotify splits its history into "
                + "smaller files: add them one at a time."
        )
        if case let .known(length) = body.length, length > limit {
            throw tooLarge
        }
        let data: Data
        do {
            data = try await Data(collecting: body, upTo: limit)
        } catch {
            throw tooLarge
        }
        let job = try await services.imports.createListenFileImport(
            userID: currentUser(), source: source, filename: query.filename, data: data
        )
        return .accepted(.init(body: .json(.init(job))))
    }

    func createLastFMImport(_ input: Operations.CreateLastFMImport.Input) async throws
        -> Operations.CreateLastFMImport.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let job = try await services.imports.createListenAccountImport(
            userID: currentUser(), source: .lastFM, username: body.username
        )
        return .accepted(.init(body: .json(.init(job))))
    }

    func createListenBrainzImport(_ input: Operations.CreateListenBrainzImport.Input) async throws
        -> Operations.CreateListenBrainzImport.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let job = try await services.imports.createListenAccountImport(
            userID: currentUser(), source: .listenBrainz, username: body.username
        )
        return .accepted(.init(body: .json(.init(job))))
    }

    func undoListenImport(_ input: Operations.UndoListenImport.Input) async throws
        -> Operations.UndoListenImport.Output
    {
        try await services.imports.undoListens(importID(input.path.id), userID: currentUser())
        return .noContent(.init())
    }

    func createCATImport(_ input: Operations.CreateCATImport.Input) async throws -> Operations.CreateCATImport
        .Output
    {
        let body: HTTPBody = switch input.body {
        case let .plainText(body), let .textCalendar(body): body
        }
        let text = try await Self.text(body)
        let job = try await services.imports.createCATImport(userID: currentUser(), text: text)
        return .accepted(.init(body: .json(.init(job))))
    }

    func createCATFeedImport(_ input: Operations.CreateCATFeedImport.Input) async throws
        -> Operations.CreateCATFeedImport.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let job = try await services.imports.createCATFeedImport(userID: currentUser(), link: body.url)
        return .accepted(.init(body: .json(.init(job))))
    }

    func createCaptureImport(_ input: Operations.CreateCaptureImport.Input) async throws
        -> Operations.CreateCaptureImport.Output
    {
        let request: ImportService.CaptureRequest
        switch input.body {
        case let .json(body):
            switch (body.text, body.url) {
            case let (text?, nil): request = .text(text)
            case let (nil, url?): request = .link(url)
            default:
                throw AppError(
                    status: .unprocessableContent, code: "validation_failed", message: "Send text or a link, not both.",
                    details: ["body": "Exactly one of text and url."]
                )
            }
        case let .jpeg(body): request = try await .image(Self.image(body), mediaType: "image/jpeg")
        case let .png(body): request = try await .image(Self.image(body), mediaType: "image/png")
        case let .imageGif(body): request = try await .image(Self.image(body), mediaType: "image/gif")
        case let .imageWebp(body): request = try await .image(Self.image(body), mediaType: "image/webp")
        }
        let job = try await services.imports.createCapture(userID: currentUser(), request)
        return .accepted(.init(body: .json(.init(job))))
    }

    func getImport(_ input: Operations.GetImport.Input) async throws -> Operations.GetImport.Output {
        let detail = try await services.imports.detail(importID(input.path.id), userID: currentUser())
        return .ok(.init(body: .json(.init(
            job: .init(detail.job),
            rows: detail.rows.map(Components.Schemas.ImportRow.init)
        ))))
    }

    func deleteImport(_ input: Operations.DeleteImport.Input) async throws -> Operations.DeleteImport.Output {
        try await services.imports.delete(importID(input.path.id), userID: currentUser())
        return .noContent(.init())
    }

    func applyImport(_ input: Operations.ApplyImport.Input) async throws -> Operations.ApplyImport.Output {
        let job = try await services.imports.apply(importID(input.path.id), userID: currentUser())
        return .ok(.init(body: .json(.init(job))))
    }

    func resolveImportRow(_ input: Operations.ResolveImportRow.Input) async throws
        -> Operations.ResolveImportRow.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let resolved = try await services.imports.resolveRow(
            importID(input.path.id), index: input.path.index, to: MediaRef(body.mediaRef), userID: currentUser()
        )
        return .ok(.init(body: .json(.init(job: .init(resolved.job), row: .init(resolved.row)))))
    }

    func createAniListImport(_ input: Operations.CreateAniListImport.Input) async throws
        -> Operations.CreateAniListImport.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let job = try await services.imports.createAniListImport(userID: currentUser(), username: body.username)
        return .accepted(.init(body: .json(.init(job))))
    }

    func startStremioLink(_: Operations.StartStremioLink.Input) async throws -> Operations.StartStremioLink.Output {
        let link = try await services.imports.startStremioLink(userID: currentUser())
        return .ok(.init(body: .json(.init(
            code: link.code, link: link.link.absoluteString, qrcode: link.qrcode.absoluteString,
            expiresAt: link.expiresAt
        ))))
    }

    func pollStremioLink(_ input: Operations.PollStremioLink.Input) async throws -> Operations.PollStremioLink.Output {
        switch try await services.imports.pollStremioLink(code: input.path.code, userID: currentUser()) {
        case .pending: .noContent(.init())
        case let .imported(job): .accepted(.init(body: .json(.init(job))))
        }
    }

    func createTraktImport(_: Operations.CreateTraktImport.Input) async throws -> Operations.CreateTraktImport
        .Output
    {
        try await .accepted(.init(body: .json(.init(services.imports.createTraktImport(userID: currentUser())))))
    }

    func connectTrakt(_ input: Operations.ConnectTrakt.Input) async throws -> Operations.ConnectTrakt.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let url = try await services.traktConnect.start(userID: currentUser(), returnTo: body.returnTo)
        return .ok(.init(body: .json(.init(authorizeUrl: url.absoluteString))))
    }

    func getTraktConnection(_: Operations.GetTraktConnection.Input) async throws -> Operations.GetTraktConnection
        .Output
    {
        let status = try await services.traktConnect.status(userID: currentUser())
        return .ok(.init(body: .json(.init(
            connected: status.connected, username: status.username, connectedAt: status.connectedAt
        ))))
    }

    func disconnectTrakt(_: Operations.DisconnectTrakt.Input) async throws -> Operations.DisconnectTrakt.Output {
        try await services.traktConnect.disconnect(userID: currentUser())
        return .noContent(.init())
    }

    /// An upload's text. An oversized one is refused from its declared length, before a byte is read.
    private static func text(_ body: HTTPBody) async throws -> String {
        if case let .known(length) = body.length, length > ImportService.maxUploadBytes {
            throw tooLarge
        }
        do {
            return try await String(collecting: body, upTo: ImportService.maxUploadBytes)
        } catch {
            throw tooLarge
        }
    }

    /// An image's bytes, up to the same 5 MB as a file. Apps downscale before sending.
    private static func image(_ body: HTTPBody) async throws -> Data {
        let tooLarge = AppError(
            status: .contentTooLarge, code: "file_too_large", message: "That image is larger than 5 MB."
        )
        if case let .known(length) = body.length, length > ImportService.maxUploadBytes {
            throw tooLarge
        }
        do {
            return try await Data(collecting: body, upTo: ImportService.maxUploadBytes)
        } catch {
            throw tooLarge
        }
    }

    private static var tooLarge: AppError {
        AppError(
            status: .contentTooLarge, code: "file_too_large",
            message: "That file is larger than 5 MB. Exports are usually much smaller; check it is the right file."
        )
    }

    private func importID(_ raw: String) throws -> ImportJobID {
        guard let id = ImportJobID(uuidString: raw) else { throw AppError.notFound() }
        return id
    }
}

extension Components.Schemas.ImportJob {
    init(_ job: ImportJob) {
        self.init(
            id: job.id.description,
            source: .init(rawValue: job.source.rawValue) ?? .trakt,
            state: .init(rawValue: job.state.rawValue) ?? .queued,
            stats: .init(
                created: job.stats.created, updated: job.stats.updated,
                skipped: job.stats.skipped, unmatched: job.stats.unmatched,
                ignored: job.source.isListens ? job.stats.ignored : nil
            ),
            errorSummary: job.errorSummary,
            filename: job.filename,
            createdAt: job.createdAt,
            updatedAt: job.updatedAt,
            rowsTotal: job.rowsTotal,
            rowsMatched: job.rowsMatched,
            actionId: job.actionID?.uuidString.lowercased()
        )
    }
}

extension Components.Schemas.ImportRow {
    init(_ planned: PlannedRow) {
        let row = planned.row
        self.init(
            index: planned.index,
            title: row.title,
            year: row.year,
            author: row.author,
            _type: .init(row.type),
            sourceKey: row.sourceKey,
            ids: .init(row.ids),
            status: row.status.map(Components.Schemas.LibraryStatus.init),
            rating: row.rating,
            outcome: .init(rawValue: planned.outcome.rawValue) ?? .pending,
            reason: planned.reason,
            titleId: planned.titleID?.description
        )
    }
}
