import AaruCore
import FluentKit
import FluentSQL
import Foundation

// Postgres implementations of the store protocols. The only files that may
// import FluentKit / FluentSQL besides migrations and app wiring.

extension Stores {
    /// The production store set over one Fluent database.
    static func postgres(_ database: any Database) throws -> Stores {
        let sql = try sqlDatabase(database)
        return Stores(
            health: PostgresHealth(sql: sql),
            users: PostgresUserStore(database: database),
            sessions: PostgresSessionStore(sql: sql),
            magicLinks: PostgresMagicLinkStore(sql: sql),
            titles: PostgresTitleStore(sql: sql),
            library: PostgresLibraryStore(sql: sql),
            lists: PostgresListStore(database: database, sql: sql),
            importJobs: PostgresImportJobStore(sql: sql)
        )
    }
}

func sqlDatabase(_ database: any Database) throws -> any SQLDatabase {
    guard let sql = database as? any SQLDatabase else { throw MigrationNeedsSQL() }
    return sql
}

/// Runs a write and turns a unique/foreign-key violation into `StoreConflict`.
private func mappingConflicts<T>(_ message: String, _ body: () async throws -> T) async throws -> T {
    do {
        return try await body()
    } catch let error as any DatabaseError where error.isConstraintFailure {
        throw StoreConflict(message: message)
    }
}

struct PostgresHealth: DatabaseHealth {
    let sql: any SQLDatabase

    func isReachable() async -> Bool {
        (try? await sql.raw("SELECT 1").run()) != nil
    }
}

struct PostgresUserStore: UserStore {
    let database: any Database

    func createUser(with identity: AuthIdentity, displayName: String?) async throws -> UserID {
        let userID = UserID()
        try await mappingConflicts("That sign-in is already linked to an account.") {
            try await database.transaction { database in
                let sql = try sqlDatabase(database)
                try await sql.insert(into: "users").columns("id", "display_name")
                    .values(SQLBind(userID.rawValue), SQLBind(displayName)).run()
                try await sql.insert(into: "auth_identities")
                    .columns("id", "user_id", "provider", "provider_subject", "email")
                    .values(
                        SQLBind(UUID()),
                        SQLBind(userID.rawValue),
                        SQLBind(identity.provider.rawValue),
                        SQLBind(identity.subject),
                        SQLBind(identity.email)
                    )
                    .run()
            }
        }
        return userID
    }

    func user(for provider: AuthIdentity.Provider, subject: String) async throws -> UserID? {
        struct Row: Decodable { let userId: UUID }
        let row = try await sqlDatabase(database).select().column("user_id").from("auth_identities")
            .where("provider", .equal, provider.rawValue)
            .where("provider_subject", .equal, subject)
            .first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        return row.map { UserID($0.userId) }
    }
}

struct PostgresTitleStore: TitleStore {
    let sql: any SQLDatabase

    private struct Row: Codable {
        let id: UUID
        let type: String
        let title: String
        let originalTitle: String?
        let year: Int?
        let synopsis: String?
        let posterUrl: String?
        let tmdb, imdb, trakt, tvdb, isbn, openLibrary: String?
    }

    func insert(_ title: Title) async throws {
        try title.validate()
        let row = Row(
            id: title.id.rawValue,
            type: title.type.rawValue,
            title: title.title,
            originalTitle: title.originalTitle,
            year: title.year,
            synopsis: title.synopsis,
            posterUrl: title.posterURL?.absoluteString,
            tmdb: title.ids.tmdb,
            imdb: title.ids.imdb,
            trakt: title.ids.trakt,
            tvdb: title.ids.tvdb,
            isbn: title.ids.isbn,
            openLibrary: title.ids.openLibrary
        )
        try await mappingConflicts("Another title already has one of these external ids.") {
            try await sql.insert(into: "titles").model(row, keyEncodingStrategy: .convertToSnakeCase).run()
        }
    }

    func title(id: TitleID) async throws -> Title? {
        guard let row = try await sql.select().columns(SQLLiteral.all).from("titles")
            .where("id", .equal, id.rawValue)
            .first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        else { return nil }
        guard let type = MediaType(rawValue: row.type) else { return nil }
        return Title(
            id: TitleID(row.id),
            type: type,
            title: row.title,
            originalTitle: row.originalTitle,
            year: row.year,
            synopsis: row.synopsis,
            posterURL: row.posterUrl.flatMap(URL.init(string:)),
            ids: ExternalIDs(
                tmdb: row.tmdb,
                imdb: row.imdb,
                trakt: row.trakt,
                tvdb: row.tvdb,
                isbn: row.isbn,
                openLibrary: row.openLibrary
            )
        )
    }
}

struct PostgresLibraryStore: LibraryStore {
    let sql: any SQLDatabase

    private struct Row: Codable {
        let id: UUID
        let userId: UUID
        let titleId: UUID
        let status: String
        let isOwned: Bool
        let rating: Double?
        let notes: String?
        let addedAt: Date
        let updatedAt: Date
        let finishedAt: Date?
    }

    func insert(_ item: LibraryItem) async throws {
        let row = Row(
            id: item.id.rawValue,
            userId: item.userID.rawValue,
            titleId: item.titleID.rawValue,
            status: item.status.rawValue,
            isOwned: item.isOwned,
            rating: item.rating?.value,
            notes: item.notes,
            addedAt: item.addedAt,
            updatedAt: item.updatedAt,
            finishedAt: item.finishedAt
        )
        try await mappingConflicts("This title is already in the library.") {
            try await sql.insert(into: "library_items").model(row, keyEncodingStrategy: .convertToSnakeCase).run()
        }
    }

    func item(id: LibraryItemID, userID: UserID) async throws -> LibraryItem? {
        guard let row = try await sql.select().columns(SQLLiteral.all).from("library_items")
            .where("id", .equal, id.rawValue)
            .where("user_id", .equal, userID.rawValue)
            .first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase),
            let status = LibraryStatus(rawValue: row.status)
        else { return nil }
        return try LibraryItem(
            id: LibraryItemID(row.id),
            userID: UserID(row.userId),
            titleID: TitleID(row.titleId),
            status: status,
            isOwned: row.isOwned,
            rating: row.rating.map(Rating.init),
            notes: row.notes,
            addedAt: row.addedAt,
            updatedAt: row.updatedAt,
            finishedAt: row.finishedAt
        )
    }
}

struct PostgresListStore: ListStore {
    let database: any Database
    let sql: any SQLDatabase

    private struct Row: Codable {
        let id: UUID
        let userId: UUID
        let name: String
        let createdAt: Date
        let updatedAt: Date
    }

    func create(_ list: AaruList) async throws {
        try list.validate()
        let row = Row(
            id: list.id.rawValue,
            userId: list.userID.rawValue,
            name: list.name,
            createdAt: list.createdAt,
            updatedAt: list.updatedAt
        )
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            try await sql.insert(into: "lists").model(row, keyEncodingStrategy: .convertToSnakeCase).run()
            for (position, titleID) in list.titleIDs.enumerated() {
                try await sql.insert(into: "list_items")
                    .columns("id", "list_id", "title_id", "position")
                    .values(SQLBind(UUID()), SQLBind(list.id.rawValue), SQLBind(titleID.rawValue), SQLBind(position))
                    .run()
            }
        }
    }

    func lists(userID: UserID) async throws -> [AaruList] {
        struct Member: Decodable {
            let listId: UUID
            let titleId: UUID
        }
        let rows = try await sql.select().columns(SQLLiteral.all).from("lists")
            .where("user_id", .equal, userID.rawValue)
            .orderBy("created_at")
            .all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        guard !rows.isEmpty else { return [] }
        let members = try await sql.select().columns("list_id", "title_id").from("list_items")
            .where("list_id", .in, rows.map(\.id))
            .orderBy("position")
            .all(decoding: Member.self, keyDecodingStrategy: .convertFromSnakeCase)
        let byList = Dictionary(grouping: members, by: \.listId)
        return rows.map { row in
            AaruList(
                id: ListID(row.id),
                userID: UserID(row.userId),
                name: row.name,
                titleIDs: (byList[row.id] ?? []).map { TitleID($0.titleId) },
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            )
        }
    }
}

struct PostgresImportJobStore: ImportJobStore {
    let sql: any SQLDatabase

    private struct Row: Codable {
        let id: UUID
        let userId: UUID
        let source: String
        let state: String
        let stats: ImportStats
        let errorSummary: String?
        let createdAt: Date
        let updatedAt: Date
    }

    private func row(_ job: ImportJob) -> Row {
        Row(
            id: job.id.rawValue,
            userId: job.userID.rawValue,
            source: job.source.rawValue,
            state: job.state.rawValue,
            stats: job.stats,
            errorSummary: job.errorSummary,
            createdAt: job.createdAt,
            updatedAt: job.updatedAt
        )
    }

    func insert(_ job: ImportJob) async throws {
        try await sql.insert(into: "import_jobs").model(row(job), keyEncodingStrategy: .convertToSnakeCase).run()
    }

    func update(_ job: ImportJob) async throws {
        try await sql.update("import_jobs")
            .set("state", to: job.state.rawValue)
            .set("stats", to: job.stats)
            .set("error_summary", to: job.errorSummary)
            .set("updated_at", to: job.updatedAt)
            .where("id", .equal, job.id.rawValue)
            .where("user_id", .equal, job.userID.rawValue)
            .run()
    }

    func job(id: ImportJobID, userID: UserID) async throws -> ImportJob? {
        guard let row = try await sql.select().columns(SQLLiteral.all).from("import_jobs")
            .where("id", .equal, id.rawValue)
            .where("user_id", .equal, userID.rawValue)
            .first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase),
            let source = ImportSource(rawValue: row.source),
            let state = ImportJobState(rawValue: row.state)
        else { return nil }
        return ImportJob(
            id: ImportJobID(row.id),
            userID: UserID(row.userId),
            source: source,
            state: state,
            stats: row.stats,
            errorSummary: row.errorSummary,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt
        )
    }
}
