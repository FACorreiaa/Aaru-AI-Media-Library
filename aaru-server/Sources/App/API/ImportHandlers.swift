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
        // Refuse an oversized upload from its declared length, before reading a byte of it.
        if case let .known(length) = body.length, length > ImportService.maxUploadBytes {
            throw Self.tooLarge
        }
        let text: String
        do {
            text = try await String(collecting: body, upTo: ImportService.maxUploadBytes)
        } catch {
            throw Self.tooLarge
        }
        let source: ImportSource = switch input.query.source {
        case .imdb: .imdbCSV
        case .letterboxd: .letterboxdCSV
        case .goodreads: .goodreadsCSV
        case .mal: .malXML
        }
        let job = try await services.imports.createCSVImport(
            userID: currentUser(), source: source, filename: input.query.filename, text: text
        )
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
            updatedAt: job.updatedAt
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
