import AaruCore
import Foundation

// MARK: AniList (IMP-014)

extension ImportService {
    /// The uploaded file's rows: MyAnimeList XML or one of the CSV layouts.
    static func parse(_ text: String, source: ImportSource, filename: String?) throws -> [ImportRow] {
        source == .malXML
            ? try MALListParser.parse(text)
            : try CSVImportParser.parse(text, source: source, filename: filename)
    }

    /// AniList usernames: 2–20 letters, digits or underscores.
    static func validAniListName(_ name: String) -> Bool {
        (2 ... 20).contains(name.count) && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    /// An AniList import job. Its rows are read from AniList by the worker, not now. The username
    /// is kept in the job's `filename`, which is what the import list shows.
    func createAniListImport(userID: UserID, username: String) async throws -> ImportJob {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: ["@"])
        guard Self.validAniListName(name) else {
            let message = "Enter your AniList username: 2–20 letters, digits or underscores."
            throw AppError(
                status: .unprocessableContent, code: "validation_failed", message: message,
                details: ["username": message]
            )
        }
        let job = ImportJob(userID: userID, source: .anilist, filename: name, createdAt: now(), updatedAt: now())
        try await stores.importJobs.insert(job, rows: [])
        return job
    }

    /// Reads the public list. A private list or unknown user fails the job at once, with a message
    /// the person can act on, instead of retrying.
    func fetchAniList(_ job: inout ImportJob) async throws -> [ImportRow]? {
        func fail(_ message: String) async throws -> [ImportRow]? {
            job.state = .failed
            job.errorSummary = message
            job.updatedAt = now()
            try await stores.importJobs.update(job)
            return nil
        }
        guard let reader = anilistLists, let name = job.filename else {
            return try await fail("AniList import is not available right now.")
        }
        do {
            let rows = try await reader.animeRows(userName: name)
            return rows.isEmpty ? try await fail("\(name)'s AniList anime list is empty.") : rows
        } catch let error as ProviderError where error.kind == .notFound {
            return try await fail(
                "AniList has no public anime list for “\(name)”. Check the username, or make the list public "
                    + "in AniList's settings, then import again."
            )
        }
    }
}
