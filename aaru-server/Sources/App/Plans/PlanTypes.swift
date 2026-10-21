import AaruCore
import Foundation

/// AG-003 / OUT-004 · a change an outside agent asked for that is bigger than a tap. It waits
/// in Aaru until the user approves or denies it; nothing is written before that.
struct AgentPlan: Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case pending, applied, denied, stale, expired
    }

    /// One line of the plan as the user reads it.
    struct Change: Codable, Sendable, Equatable {
        var text: String
        var titleID: TitleID
        var title: String
        var type: MediaType
        var posterURL: String?
        /// Nil for an add: the item does not exist yet.
        var libraryItemID: LibraryItemID?
    }

    struct Counts: Codable, Sendable, Equatable {
        var adds = 0
        var updates = 0
        var removes = 0
        var episodes = 0
    }

    /// What the library looked like when the plan was made. Approval checks it again, so a
    /// plan never lands on a library that moved under it.
    struct Basis: Codable, Sendable, Equatable {
        /// Each touched item's `updated_at` in microseconds, by lowercase item id.
        var items: [String: Int64] = [:]
        /// Titles the plan adds, which must still be absent.
        var absentTitles: [UUID] = []
    }

    var id: UUID
    var agentTokenID: UUID?
    var agentName: String
    var status: Status
    var summary: String
    var changes: [Change]
    var counts: Counts
    var op: LibraryOp
    var basis: Basis
    var createdAt: Date
    var expiresAt: Date
    var decidedAt: Date?
    var actionID: UUID?

    /// Pending, but past its expiry: it can no longer be approved.
    func isExpired(at now: Date) -> Bool {
        status == .pending && expiresAt <= now
    }
}

/// How an approval ended. Only `applied` wrote anything.
enum PlanDecision: Sendable {
    case applied(AgentPlan, ActionRecord)
    case denied(AgentPlan)
    case stale(AgentPlan)
    case expired(AgentPlan)
    case alreadyDecided(AgentPlan)
}

protocol PlanStore: Sendable {
    func create(_ plan: AgentPlan, userID: UserID) async throws
    /// The user's plans, newest first: only pending ones (expired ones excluded), or all.
    func plans(userID: UserID, pendingOnly: Bool, now: Date, limit: Int) async throws -> [AgentPlan]
    func plan(id: UUID, userID: UserID) async throws -> AgentPlan?
    /// Plans this token has waiting, so one agent cannot flood the user.
    func pendingCount(agentTokenID: UUID, now: Date) async throws -> Int
    /// Each item's `updated_at` in microseconds, for a plan's basis.
    func itemVersions(_ ids: [LibraryItemID], userID: UserID) async throws -> [String: Int64]
    /// In one transaction: re-checks status, expiry and basis, then runs the op and journals it
    /// as the plan's token. Nil when the user has no such plan.
    func approve(id: UUID, userID: UserID, now: Date) async throws -> PlanDecision?
    /// Nil when the user has no such plan; `alreadyDecided` when it is not pending.
    func deny(id: UUID, userID: UserID, now: Date) async throws -> PlanDecision?
}
