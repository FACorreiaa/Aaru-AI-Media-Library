import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// Import jobs as a leased queue (JOB-001) plus their parsed rows (IMP-001).
struct PostgresImportJobStore: ImportJobStore {
    let sql: any SQLDatabase

    private struct Row: Codable {
        let id: UUID
        let userId: UUID
        let source: String
        let state: String
        let stats: ImportStats
        let errorSummary: String?
        let filename: String?
        let createdAt: Date
        let updatedAt: Date
        var attempts: Int?

        var job: ImportJob? {
            guard let source = ImportSource(rawValue: source), let state = ImportJobState(rawValue: state)
            else { return nil }
            return ImportJob(
                id: ImportJobID(id), userID: UserID(userId), source: source, state: state, stats: stats,
                errorSummary: errorSummary, filename: filename, createdAt: createdAt, updatedAt: updatedAt
            )
        }
    }

    private static let columns: SQLQueryString =
        "id, user_id, source, state, stats, error_summary, filename, created_at, updated_at, attempts"

    func insert(_ job: ImportJob) async throws {
        try await insert(job, on: sql)
    }

    func insert(_ job: ImportJob, rows: [ImportRow]) async throws {
        try await sql.transaction { sql in
            try await insert(job, on: sql)
            for (index, row) in rows.enumerated() {
                try await sql.raw("""
                INSERT INTO import_rows (job_id, idx, row)
                VALUES (\(bind: job.id.rawValue), \(bind: index), \(bind: row))
                """).run()
            }
        }
    }

    private func insert(_ job: ImportJob, on sql: any SQLDatabase) async throws {
        try await sql.raw("""
        INSERT INTO import_jobs (id, user_id, source, state, stats, error_summary, filename, created_at, updated_at)
        VALUES (\(bind: job.id.rawValue), \(bind: job.userID.rawValue), \(bind: job.source.rawValue),
            \(bind: job.state.rawValue), \(bind: job.stats), \(bind: job.errorSummary), \(bind: job.filename),
            \(bind: job.createdAt), \(bind: job.updatedAt))
        """).run()
    }

    func update(_ job: ImportJob) async throws {
        try await sql.raw("""
        UPDATE import_jobs SET state = \(bind: job.state.rawValue), stats = \(bind: job.stats),
            error_summary = \(bind: job.errorSummary), updated_at = \(bind: job.updatedAt), locked_until = NULL
        WHERE id = \(bind: job.id.rawValue) AND user_id = \(bind: job.userID.rawValue)
        """).run()
    }

    func job(id: ImportJobID, userID: UserID) async throws -> ImportJob? {
        try await sql.raw("""
        SELECT \(Self.columns) FROM import_jobs WHERE id = \(bind: id.rawValue) AND user_id = \(bind: userID.rawValue)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)?.job
    }

    func jobs(userID: UserID, limit: Int) async throws -> [ImportJob] {
        try await sql.raw("""
        SELECT \(Self.columns) FROM import_jobs WHERE user_id = \(bind: userID.rawValue)
        ORDER BY created_at DESC LIMIT \(literal: max(1, min(limit, 100)))
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).compactMap(\.job)
    }

    func claimNext(now: Date, lease: TimeInterval) async throws -> ClaimedImportJob? {
        // One statement: SKIP LOCKED means two workers never lease the same job.
        guard let row = try await sql.raw("""
        UPDATE import_jobs SET state = 'running', attempts = attempts + 1,
            locked_until = \(bind: now.addingTimeInterval(lease)), updated_at = \(bind: now)
        WHERE id = (
            SELECT id FROM import_jobs
            WHERE (state = 'queued' AND (locked_until IS NULL OR locked_until <= \(bind: now)))
               OR (state = 'running' AND locked_until < \(bind: now))
            ORDER BY created_at
            FOR UPDATE SKIP LOCKED
            LIMIT 1
        )
        RETURNING \(Self.columns)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase),
            let job = row.job
        else { return nil }
        return ClaimedImportJob(job: job, attempts: row.attempts ?? 1)
    }

    func retry(_ id: ImportJobID, error: String, notBefore: Date, now: Date) async throws {
        try await sql.raw("""
        UPDATE import_jobs SET state = 'queued', error_summary = \(bind: error),
            locked_until = \(bind: notBefore), updated_at = \(bind: now)
        WHERE id = \(bind: id.rawValue)
        """).run()
    }

    func rows(jobID: ImportJobID) async throws -> [PlannedRow] {
        struct Stored: Decodable {
            let idx: Int
            let row: ImportRow
            let outcome: String
            let reason: String?
            let titleId: UUID?
        }
        return try await sql.raw("""
        SELECT idx, row, outcome, reason, title_id FROM import_rows
        WHERE job_id = \(bind: jobID.rawValue) ORDER BY idx
        """).all(decoding: Stored.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            PlannedRow(
                index: $0.idx, row: $0.row, outcome: ImportOutcome(rawValue: $0.outcome) ?? .pending,
                reason: $0.reason, titleID: $0.titleId.map(TitleID.init)
            )
        }
    }

    func savePlan(_ job: ImportJob, rows: [PlannedRow]) async throws {
        try await sql.transaction { sql in
            for row in rows {
                try await sql.raw("""
                UPDATE import_rows SET outcome = \(bind: row.outcome.rawValue), reason = \(bind: row.reason),
                    title_id = \(bind: row.titleID?.rawValue)
                WHERE job_id = \(bind: job.id.rawValue) AND idx = \(bind: row.index)
                """).run()
            }
            try await sql.raw("""
            UPDATE import_jobs SET state = \(bind: job.state.rawValue), stats = \(bind: job.stats),
                error_summary = \(bind: job.errorSummary), updated_at = \(bind: job.updatedAt), locked_until = NULL
            WHERE id = \(bind: job.id.rawValue)
            """).run()
        }
    }

    func delete(id: ImportJobID, userID: UserID) async throws -> Bool {
        struct Deleted: Decodable { let id: UUID }
        return try await sql.raw("""
        DELETE FROM import_jobs WHERE id = \(bind: id.rawValue) AND user_id = \(bind: userID.rawValue) RETURNING id
        """).first(decoding: Deleted.self) != nil
    }
}

private extension SQLDatabase {
    func transaction<T: Sendable>(_ body: @Sendable @escaping (any SQLDatabase) async throws -> T) async throws -> T {
        guard let database = self as? any Database else { return try await body(self) }
        return try await database.transaction { try await body(sqlDatabase($0)) }
    }
}
