import AaruCore
import Foundation

// `@aaru` in groups (GRP-010 / GRP-011).

enum AgentReplyState: String, Sendable {
    case queued
    case running
    case done
    case failed
    /// Over the fair-use cap: answered once with the "resting" note, no model call.
    case capped
    /// Over the cap after the note was already given: no answer at all.
    case skipped
}

/// One mention to answer.
struct AgentReplyJob: Sendable, Equatable {
    var id: UUID
    var messageID: UUID
    var groupID: UUID
    var channelID: UUID
    var tagger: UserID
    var attempts: Int
}

/// What the fair-use caps look at.
struct AgentLoad: Sendable, Equatable {
    /// Mentions by the user since the start of the day that reached the model, or will.
    var userToday: Int
    /// Mentions in the group over the last hour that reached the model, or will.
    var groupHour: Int
    /// The user already got the "resting" note today.
    var userNoted: Bool
    /// The group already got it this hour.
    var groupNoted: Bool
}

struct AgentUsage: Sendable, Equatable {
    var requests: Int
    var inputTokens: Int
    var outputTokens: Int
}

protocol AgentStore: Sendable {
    func enqueue(_ job: AgentReplyJob, state: AgentReplyState, now: Date) async throws
    func load(tagger: UserID, group: UUID, dayStart: Date, hourStart: Date) async throws -> AgentLoad
    /// Leases the oldest queued job, or one whose lease ran out.
    func claim(now: Date, lease: TimeInterval) async throws -> AgentReplyJob?
    func finish(_ id: UUID, state: AgentReplyState, error: String?, now: Date) async throws
    func retry(_ id: UUID, error: String, notBefore: Date, now: Date) async throws
    /// Adds one model call to the user's row for that UTC day.
    func recordUsage(_ user: UserID, day: Date, inputTokens: Int, outputTokens: Int) async throws
    func usage(_ user: UserID, day: Date) async throws -> AgentUsage
}
