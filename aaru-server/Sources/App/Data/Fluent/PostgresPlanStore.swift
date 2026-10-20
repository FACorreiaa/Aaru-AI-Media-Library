import AaruCore
import FluentKit
import FluentSQL
import Foundation

struct PostgresPlanStore: PlanStore {
    /// A Swift array binds as `jsonb[]`; the column holds one JSON object.
    private struct Changes: Codable {
        var items: [AgentPlan.Change]
    }

    let database: any Database

    private struct Row: Decodable {
        let id: UUID
        let agentTokenId: UUID?
        let agentName: String
        let status: String
        let summary: String
        let changes: Changes
        let counts: AgentPlan.Counts
        let op: LibraryOp
        let basis: AgentPlan.Basis
        let createdAt: Date
        let expiresAt: Date
        let decidedAt: Date?
        let actionId: UUID?

        var plan: AgentPlan? {
            guard let status = AgentPlan.Status(rawValue: status) else { return nil }
            return AgentPlan(
                id: id, agentTokenID: agentTokenId, agentName: agentName, status: status, summary: summary,
                changes: changes.items, counts: counts, op: op, basis: basis, createdAt: createdAt,
                expiresAt: expiresAt, decidedAt: decidedAt, actionID: actionId
            )
        }
    }

    private static let columns = """
    id, agent_token_id, agent_name, status, summary, changes, counts, op, basis, created_at, expires_at,
    decided_at, action_id
    """

    func create(_ plan: AgentPlan, userID: UserID) async throws {
        try await sqlDatabase(database).raw("""
        INSERT INTO agent_plans (id, user_id, agent_token_id, agent_name, status, summary, changes, counts, op,
            basis, created_at, expires_at)
        VALUES (\(bind: plan.id), \(bind: userID.rawValue), \(bind: plan.agentTokenID), \(bind: plan.agentName),
            \(bind: plan.status.rawValue), \(bind: plan.summary), \(bind: Changes(items: plan.changes)),
            \(bind: plan.counts),
            \(bind: plan.op), \(bind: plan.basis), \(bind: plan.createdAt), \(bind: plan.expiresAt))
        """).run()
    }

    func plans(userID: UserID, pendingOnly: Bool, now: Date, limit: Int) async throws -> [AgentPlan] {
        let sql = try sqlDatabase(database)
        let rows = if pendingOnly {
            try await sql.raw("""
            SELECT \(unsafeRaw: Self.columns) FROM agent_plans
            WHERE user_id = \(bind: userID.rawValue) AND status = 'pending' AND expires_at > \(bind: now)
            ORDER BY created_at DESC LIMIT \(bind: limit)
            """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        } else {
            try await sql.raw("""
            SELECT \(unsafeRaw: Self.columns) FROM agent_plans
            WHERE user_id = \(bind: userID.rawValue)
            ORDER BY created_at DESC LIMIT \(bind: limit)
            """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        }
        return rows.compactMap(\.plan)
    }

    func plan(id: UUID, userID: UserID) async throws -> AgentPlan? {
        try await sqlDatabase(database).raw("""
        SELECT \(unsafeRaw: Self.columns) FROM agent_plans
        WHERE id = \(bind: id) AND user_id = \(bind: userID.rawValue)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)?.plan
    }

    func pendingCount(agentTokenID: UUID, now: Date) async throws -> Int {
        struct CountRow: Decodable { let count: Int }
        return try await sqlDatabase(database).raw("""
        SELECT count(*)::int AS count FROM agent_plans
        WHERE agent_token_id = \(bind: agentTokenID) AND status = 'pending' AND expires_at > \(bind: now)
        """).first(decoding: CountRow.self)?.count ?? 0
    }

    func itemVersions(_ ids: [LibraryItemID], userID: UserID) async throws -> [String: Int64] {
        guard !ids.isEmpty else { return [:] }
        return try await Self.versions(ids.map(\.rawValue), userID: userID, sql: sqlDatabase(database), lock: false)
    }

    func approve(id: UUID, userID: UserID, now: Date) async throws -> PlanDecision? {
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            guard let plan = try await Self.locked(id, userID: userID, sql: sql) else { return nil }
            guard plan.status == .pending else { return .alreadyDecided(plan) }
            if plan.isExpired(at: now) {
                return try await .expired(Self.decide(plan, .expired, now: now, sql: sql))
            }
            guard try await Self.basisHolds(plan.basis, userID: userID, sql: sql) else {
                return try await .stale(Self.decide(plan, .stale, now: now, sql: sql))
            }
            let inverse = try await PostgresLibraryStore.run(plan.op, userID: userID, sql: sql)
            let caller = Caller(actor: .externalAgent, agentTokenID: plan.agentTokenID, agentName: plan.agentName)
            let action = try await PostgresLibraryStore.journal(
                .init(
                    inverse: inverse, itemIDs: plan.op.itemIDs, actor: .externalAgent, kind: "plan",
                    summary: caller.summary(plan.summary), undoOf: nil, agentTokenID: plan.agentTokenID
                ),
                userID: userID, sql: sql
            )
            return try await .applied(Self.decide(plan, .applied, now: now, actionID: action.id, sql: sql), action)
        }
    }

    func deny(id: UUID, userID: UserID, now: Date) async throws -> PlanDecision? {
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            guard let plan = try await Self.locked(id, userID: userID, sql: sql) else { return nil }
            guard plan.status == .pending else { return .alreadyDecided(plan) }
            return try await .denied(Self.decide(plan, .denied, now: now, sql: sql))
        }
    }

    // MARK: Transaction steps

    private static func locked(_ id: UUID, userID: UserID, sql: any SQLDatabase) async throws -> AgentPlan? {
        try await sql.raw("""
        SELECT \(unsafeRaw: columns) FROM agent_plans
        WHERE id = \(bind: id) AND user_id = \(bind: userID.rawValue) FOR UPDATE
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)?.plan
    }

    private static func decide(
        _ plan: AgentPlan,
        _ status: AgentPlan.Status,
        now: Date,
        actionID: UUID? = nil,
        sql: any SQLDatabase
    ) async throws -> AgentPlan {
        try await sql.raw("""
        UPDATE agent_plans SET status = \(bind: status.rawValue), decided_at = \(bind: now),
            action_id = \(bind: actionID)
        WHERE id = \(bind: plan.id)
        """).run()
        var decided = plan
        decided.status = status
        decided.decidedAt = now
        decided.actionID = actionID
        return decided
    }

    /// Every item still exists unchanged, and no title the plan adds is in the library yet.
    private static func basisHolds(_ basis: AgentPlan.Basis, userID: UserID, sql: any SQLDatabase) async throws
        -> Bool
    {
        let ids = basis.items.keys.compactMap(UUID.init(uuidString:))
        if !ids.isEmpty {
            let current = try await versions(ids, userID: userID, sql: sql, lock: true)
            guard current == basis.items else { return false }
        }
        guard !basis.absentTitles.isEmpty else { return true }
        struct Present: Decodable { let id: UUID }
        return try await sql.raw("""
        SELECT id FROM library_items
        WHERE user_id = \(bind: userID.rawValue) AND title_id = ANY(\(bind: basis.absentTitles)) LIMIT 1
        """).first(decoding: Present.self) == nil
    }

    private static func versions(_ ids: [UUID], userID: UserID, sql: any SQLDatabase, lock: Bool) async throws
        -> [String: Int64]
    {
        struct Version: Decodable {
            let id: UUID
            let micros: Int64
        }
        let rows = try await sql.raw("""
        SELECT id, (extract(epoch FROM updated_at) * 1000000)::bigint AS micros FROM library_items
        WHERE user_id = \(bind: userID.rawValue) AND id = ANY(\(bind: ids))
        \(unsafeRaw: lock ? "FOR UPDATE" : "")
        """).all(decoding: Version.self)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id.uuidString.lowercased(), $0.micros) })
    }
}
