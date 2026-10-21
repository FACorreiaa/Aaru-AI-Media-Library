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
        let body: HTTPBody = switch input.body {
        case let .csv(body), let .xml(body): body
        }
        let text = try await Self.text(body)
        let source: ImportSource
        switch input.query.source {
        case .imdb: source = .imdbCSV
        case .letterboxd: source = .letterboxdCSV
        case .netflix: source = .netflixCSV
        case .goodreads: source = .goodreadsCSV
        case .mal: source = .malXML
        case .csv: source = .genericCSV
        case .auto:
            do {
                source = try ImportFormatDetector.detect(text)
            } catch let error as ImportFormatError {
                throw AppError(
                    status: .unprocessableContent, code: "validation_failed", message: error.message,
                    details: ["file": error.message]
                )
            }
        }
        let job = try await services.imports.createCSVImport(
            userID: currentUser(), source: source, filename: input.query.filename, text: text
        )
        return .accepted(.init(body: .json(.init(job))))
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
                skipped: job.stats.skipped, unmatched: job.stats.unmatched
            ),
            errorSummary: job.errorSummary,
            filename: job.filename,
            createdAt: job.createdAt,
            updatedAt: job.updatedAt,
            rowsTotal: job.rowsTotal,
            rowsMatched: job.rowsMatched
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
