import AaruCore
import Foundation

/// AG-001 `plan_import`: an agent hands Aaru a list export. It becomes an ordinary import job,
/// which the user reviews and approves in Aaru; this tool never writes the library.
extension AgentTools {
    struct ImportInput: Decodable, Sendable {
        var text: String
        var filename: String?
        var source: String?
    }

    /// Queued, never applied: Aaru matches the rows, then the user reviews and approves.
    struct ImportQueued: Encodable, Sendable {
        var applied = false
        var status = "pending_approval"
        var importId: String
        var source: String
        var message = """
        Nothing has changed yet. Aaru is matching the rows; the user reviews and approves the import in Aaru \
        (Settings → Imports). Tell them it is waiting there.
        """
    }

    func planImport(_ input: ImportInput, caller: AgentCaller) async throws -> any Encodable & Sendable {
        guard caller.has(.importsWrite) else {
            throw AgentToolError(message: """
            This connection cannot hand Aaru imports. The user can allow imports when connecting it in \
            Aaru → Settings → Connections.
            """)
        }
        guard input.text.utf8.count <= ImportService.maxUploadBytes else {
            throw AgentToolError(message: "text is at most 5 MB.")
        }
        let source = try Self.importSource(input.source ?? "auto", text: input.text)
        let job = try await services.imports.createCSVImport(
            userID: caller.userID, source: source, filename: input.filename, text: input.text
        )
        await services.plans.push?.send(PushMessage(
            title: "\(caller.token.name) sent you an import",
            body: "Review it in Aaru before anything is added.",
            payload: ["importId": job.id.description]
        ), userID: caller.userID)
        return ImportQueued(importId: job.id.description, source: source.rawValue)
    }

    /// The tool's `source` argument as an import source; `auto` and `cat` look at the text.
    static func importSource(_ name: String, text: String) throws -> ImportSource {
        switch name {
        case "imdb": return .imdbCSV
        case "letterboxd": return .letterboxdCSV
        case "netflix": return .netflixCSV
        case "goodreads": return .goodreadsCSV
        case "mal": return .malXML
        case "csv": return .genericCSV
        case "cat": return CATCalendarParser.isCalendar(text) ? .catICS : .catList
        case "auto":
            do {
                return try ImportFormatDetector.detect(text)
            } catch let error as ImportFormatError {
                throw AgentToolError(message: error.message)
            }
        default:
            throw AgentToolError(message: "source must be auto, imdb, letterboxd, netflix, goodreads, mal, csv or cat.")
        }
    }
}
