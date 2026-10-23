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
            animeMappings: PostgresAnimeMappingStore(sql: sql),
            library: PostgresLibraryStore(database: database),
            lists: PostgresListStore(sql: sql),
            shelves: PostgresShelfStore(sql: sql),
            schedule: PostgresScheduleStore(sql: sql),
            stats: PostgresStatsStore(sql: sql),
            importJobs: PostgresImportJobStore(sql: sql),
            trakt: PostgresTraktStore(sql: sql),
            push: PostgresPushStore(sql: sql),
            agentTokens: PostgresAgentTokenStore(sql: sql),
            watchEvents: PostgresWatchEventStore(sql: sql),
            listens: PostgresListenStore(database: database),
            plans: PostgresPlanStore(database: database),
            oauth: PostgresOAuthStore(database: database),
            social: PostgresSocialStore(database: database),
            friendViews: PostgresFriendViewStore(sql: sql),
            interactions: PostgresInteractionStore(sql: sql),
            groups: PostgresGroupStore(database: database),
            groupKinds: PostgresGroupStore(database: database),
            agent: PostgresAgentStore(sql: sql),
            concerts: PostgresConcertStore(database: database),
            gamification: PostgresGamificationStore(sql: sql),
            tonight: PostgresTonightStore(sql: sql),
            boards: PostgresBoardStore(database: database)
        )
    }
}

func sqlDatabase(_ database: any Database) throws -> any SQLDatabase {
    guard let sql = database as? any SQLDatabase else { throw MigrationNeedsSQL() }
    return sql
}

/// Runs a write and turns a unique/foreign-key violation into `StoreConflict`.
func mappingConflicts<T>(_ message: String, _ body: () async throws -> T) async throws -> T {
    do {
        return try await body()
    } catch let error as any DatabaseError where error.isConstraintFailure {
        throw StoreConflict(message: message)
    }
}

struct PostgresHealth: DatabaseHealth {
    let sql: any SQLDatabase

    func isReachable() async -> Bool {
        (try? await ping()) != nil
    }

    /// One round trip, throwing what Postgres (or the network) said: boot's wait for the database.
    func ping() async throws {
        try await sql.raw("SELECT 1").run()
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
                // A new account has no history to backfill: its first badge is a live unlock.
                try await sql.raw("""
                INSERT INTO user_progress (user_id, evaluated_at) VALUES (\(bind: userID.rawValue), now())
                """).run()
            }
        }
        return userID
    }

    func addIdentity(_ identity: AuthIdentity, to user: UserID) async throws {
        try await mappingConflicts("That sign-in is already linked to an account.") {
            try await sqlDatabase(database).insert(into: "auth_identities")
                .columns("id", "user_id", "provider", "provider_subject", "email")
                .values(
                    SQLBind(UUID()), SQLBind(user.rawValue), SQLBind(identity.provider.rawValue),
                    SQLBind(identity.subject), SQLBind(identity.email)
                )
                .run()
        }
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

struct PostgresListStore: ListStore {
    let sql: any SQLDatabase

    private struct Row: Codable {
        let id: UUID
        let userId: UUID
        let name: String
        let createdAt: Date
        let updatedAt: Date
    }

    func lists(userID: UserID) async throws -> [AaruList] {
        try await load(userID: userID, id: nil)
    }

    func list(id: ListID, userID: UserID) async throws -> AaruList? {
        try await load(userID: userID, id: id).first
    }

    private func load(userID: UserID, id: ListID?) async throws -> [AaruList] {
        struct Member: Decodable {
            let listId: UUID
            let titleId: UUID
        }
        var query = sql.select().columns(SQLLiteral.all).from("lists").where("user_id", .equal, userID.rawValue)
        if let id {
            query = query.where("id", .equal, id.rawValue)
        }
        let rows = try await query.orderBy("created_at")
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

struct PostgresShelfStore: ShelfStore {
    let sql: any SQLDatabase

    private struct Row: Codable {
        let id: UUID
        let name: String
        let filter: LibraryFilter
        let isPinned: Bool
        let createdAt: Date

        var shelf: Shelf {
            Shelf(id: id, name: name, filter: filter, isPinned: isPinned, createdAt: createdAt)
        }
    }

    func shelves(userID: UserID) async throws -> [Shelf] {
        try await sql.raw("""
        SELECT id, name, filter, is_pinned, created_at FROM saved_queries
        WHERE user_id = \(bind: userID.rawValue) ORDER BY is_pinned DESC, created_at
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.shelf)
    }

    func shelf(id: UUID, userID: UserID) async throws -> Shelf? {
        try await sql.raw("""
        SELECT id, name, filter, is_pinned, created_at FROM saved_queries
        WHERE id = \(bind: id) AND user_id = \(bind: userID.rawValue)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)?.shelf
    }

    func save(_ shelf: Shelf, userID: UserID) async throws {
        try await sql.raw("""
        INSERT INTO saved_queries (id, user_id, name, filter, is_pinned, created_at)
        VALUES (\(bind: shelf.id), \(bind: userID.rawValue), \(bind: shelf.name), \(bind: shelf.filter),
            \(bind: shelf.isPinned), \(bind: shelf.createdAt))
        ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, filter = EXCLUDED.filter,
            is_pinned = EXCLUDED.is_pinned, updated_at = now()
        WHERE saved_queries.user_id = \(bind: userID.rawValue)
        """).run()
    }

    func delete(id: UUID, userID: UserID) async throws -> Bool {
        struct Deleted: Decodable { let id: UUID }
        return try await sql.raw("""
        DELETE FROM saved_queries WHERE id = \(bind: id) AND user_id = \(bind: userID.rawValue) RETURNING id
        """).first(decoding: Deleted.self) != nil
    }
}
