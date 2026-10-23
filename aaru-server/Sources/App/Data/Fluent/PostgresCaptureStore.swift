import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// Capture inputs (AG-006): written with the job, gone once read.
struct PostgresCaptureStore: CaptureStore {
    let sql: any SQLDatabase

    func saveInput(_ input: CaptureInput) async throws {
        var text: String?
        var image: Data?
        var mediaType: String?
        switch input.content {
        case let .text(value): text = value
        case let .image(data, type): image = data; mediaType = type
        }
        try await sql.raw("""
        INSERT INTO capture_inputs (job_id, user_id, kind, text, image, media_type, created_at)
        VALUES (\(bind: input.jobID.rawValue), \(bind: input.userID.rawValue), \(bind: input.kind), \(bind: text),
                \(bind: image), \(bind: mediaType), \(bind: input.createdAt))
        """).run()
    }

    func input(jobID: ImportJobID) async throws -> CaptureInput? {
        struct Row: Decodable {
            let userId: UUID
            let text: String?
            let image: Data?
            let mediaType: String?
            let createdAt: Date
        }
        guard let row = try await sql.raw("""
        SELECT user_id, text, image, media_type, created_at FROM capture_inputs
        WHERE job_id = \(bind: jobID.rawValue)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase) else { return nil }
        let content: CaptureInput.Content
        if let image = row.image, let mediaType = row.mediaType {
            content = .image(image, mediaType: mediaType)
        } else {
            content = .text(row.text ?? "")
        }
        return CaptureInput(jobID: jobID, userID: UserID(row.userId), content: content, createdAt: row.createdAt)
    }

    func deleteInput(jobID: ImportJobID) async throws {
        try await sql.raw("DELETE FROM capture_inputs WHERE job_id = \(bind: jobID.rawValue)").run()
    }

    func sweep(before: Date) async throws -> Int {
        struct Row: Decodable { let jobId: UUID }
        return try await sql.raw("""
        DELETE FROM capture_inputs WHERE created_at < \(bind: before) RETURNING job_id
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).count
    }

    func captures(userID: UserID, since: Date) async throws -> Int {
        struct Row: Decodable { let count: Int }
        return try await sql.raw("""
        SELECT count(*)::int AS count FROM import_jobs
        WHERE user_id = \(bind: userID.rawValue) AND source = 'capture' AND created_at >= \(bind: since)
        """).first(decoding: Row.self)?.count ?? 0
    }
}
