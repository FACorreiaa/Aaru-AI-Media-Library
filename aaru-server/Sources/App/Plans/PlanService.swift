import AaruCore
import Foundation

/// AG-003's remote slice (OUT-004). An outside agent's change bigger than a tap is worked out
/// now, against the library as it is, and stored as a plan. Only the user, signed in, approves
/// or denies it; no agent token reaches these routes, so no caller approves its own plan.
struct PlanService: Sendable {
    /// A plan nobody decided on expires after this.
    static let lifetime: TimeInterval = 24 * 60 * 60
    /// Plans one token may have waiting at once.
    static let maxPendingPerToken = 20

    let stores: Stores
    let library: LibraryService
    /// Tells the user a plan is waiting. Nil in tests and when no push is configured.
    var push: UserPush?
    var now: @Sendable () -> Date = { Date() }

    func propose(_ changes: [AgentChange], caller: AgentCaller) async throws -> AgentPlan {
        let pending = try await stores.plans.pendingCount(agentTokenID: caller.token.id, now: now())
        guard pending < Self.maxPendingPerToken else {
            throw AgentToolError(message: """
            \(pending) changes from this connection are already waiting for the user. Ask them to review those \
            in Aaru first.
            """)
        }
        let writes = try await prepare(changes, caller: caller)
        guard !writes.isEmpty else {
            throw AgentToolError(message: "Nothing to change: the library already looks like that.")
        }
        var basis = AgentPlan.Basis()
        let touched = writes.filter { !$0.adds }.map(\.itemID)
        basis.items = try await stores.plans.itemVersions(touched, userID: caller.userID)
        basis.absentTitles = writes.filter(\.adds).map(\.title.id.rawValue)
        let plan = AgentPlan(
            id: UUID(), agentTokenID: caller.token.id, agentName: caller.token.name, status: .pending,
            summary: Self.summary(writes), changes: writes.map(Self.change), counts: Self.counts(writes),
            op: .batch(writes.map(\.op)), basis: basis, createdAt: now(),
            expiresAt: now().addingTimeInterval(Self.lifetime)
        )
        try await stores.plans.create(plan, userID: caller.userID)
        await push?.send(Self.message(plan), userID: caller.userID)
        return plan
    }

    func plans(userID: UserID, pendingOnly: Bool) async throws -> [AgentPlan] {
        try await stores.plans.plans(userID: userID, pendingOnly: pendingOnly, now: now(), limit: 50)
    }

    func plan(_ id: UUID, userID: UserID) async throws -> AgentPlan {
        guard let plan = try await stores.plans.plan(id: id, userID: userID) else {
            throw AppError.notFound("No such plan.")
        }
        return plan
    }

    func approve(_ id: UUID, userID: UserID) async throws -> (AgentPlan, ActionRecord) {
        guard let decision = try await stores.plans.approve(id: id, userID: userID, now: now()) else {
            throw AppError.notFound("No such plan.")
        }
        switch decision {
        case let .applied(plan, action):
            ProductEvents.capture(.agentPlanDecided, userID: userID, ["decision": "approved"])
            // Episodes for added shows, as a tap's add fetches them. Best effort.
            for change in plan.changes where change.type == .show && change.libraryItemID == nil {
                _ = try? await library.catalog.detail(change.titleID)
            }
            await GamificationService(stores: stores, now: now).batchApplied(
                userID, actionID: action.id, firstImport: false
            )
            return (plan, action)
        case let .stale(plan):
            throw AppError(
                status: .conflict, code: "plan_stale",
                message: "Your library changed since \(plan.agentName) asked, so nothing was applied. Ask it again."
            )
        case .expired:
            throw AppError(status: .conflict, code: "plan_expired", message: "This request expired. Ask again.")
        case .alreadyDecided, .denied:
            throw AppError(status: .conflict, code: "plan_decided", message: "This request was already decided.")
        }
    }

    func deny(_ id: UUID, userID: UserID) async throws -> AgentPlan {
        switch try await stores.plans.deny(id: id, userID: userID, now: now()) {
        case let .denied(plan)?:
            ProductEvents.capture(.agentPlanDecided, userID: userID, ["decision": "denied"])
            return plan
        case nil:
            throw AppError.notFound("No such plan.")
        default:
            throw AppError(status: .conflict, code: "plan_decided", message: "This request was already decided.")
        }
    }

    // MARK: Working out a plan

    /// Each change as the write a tap would make now. Changes that would do nothing are dropped.
    private func prepare(_ changes: [AgentChange], caller: AgentCaller) async throws -> [PreparedWrite] {
        let userID = caller.userID
        let agent = Caller.agent(caller.token)
        var writes: [PreparedWrite] = []
        var adding = Set<TitleID>()
        for change in changes {
            switch change {
            case let .add(ref, status):
                let title = try await library.resolver.resolve(ref)
                guard try await stores.library.item(userID: userID, titleID: title.id) == nil,
                      adding.insert(title.id).inserted
                else { continue }
                writes.append(library.prepareAdd(title, status: status, caller: agent))
            case let .update(id, patch):
                let current = try await library.entry(id, userID: userID)
                if let write = try library.preparePatch(current, patch: patch, caller: agent) {
                    writes.append(write)
                }
            case let .episodes(id, keys, season, watched):
                let show = try await library.showContext(id, userID: userID)
                if let season {
                    try await writes.append(library.prepareSeason(show, season: season))
                } else if let write = try await library.prepareEpisodes(show, keys: keys, watched: watched) {
                    writes.append(write)
                }
            case let .remove(id):
                try await writes.append(library.prepareDelete(library.entry(id, userID: userID)))
            }
        }
        return writes
    }

    static func change(_ write: PreparedWrite) -> AgentPlan.Change {
        AgentPlan.Change(
            text: write.summary, titleID: write.title.id, title: write.title.title, type: write.title.type,
            posterURL: write.title.posterURL?.absoluteString, libraryItemID: write.adds ? nil : write.itemID
        )
    }

    static func counts(_ writes: [PreparedWrite]) -> AgentPlan.Counts {
        var counts = AgentPlan.Counts()
        for write in writes {
            switch write.kind {
            case "add": counts.adds += 1
            case "remove": counts.removes += 1
            case "episode", "season": counts.episodes += write.episodes
            default: counts.updates += 1
            }
        }
        return counts
    }

    /// "Mark 18 episodes of Andor watched", or "Add 2 titles, mark 6 episodes" for several.
    static func summary(_ writes: [PreparedWrite]) -> String {
        if writes.count == 1 {
            return writes[0].summary
        }
        let counts = counts(writes)
        let parts = [
            counts.adds > 0 ? "add \(plural(counts.adds, "title"))" : nil,
            counts.episodes > 0 ? "mark \(plural(counts.episodes, "episode"))" : nil,
            counts.updates > 0 ? "update \(plural(counts.updates, "item"))" : nil,
            counts.removes > 0 ? "remove \(plural(counts.removes, "title"))" : nil,
        ].compactMap(\.self).joined(separator: ", ")
        return parts.prefix(1).uppercased() + parts.dropFirst()
    }

    private static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    static func message(_ plan: AgentPlan) -> PushMessage {
        PushMessage(
            title: "\(plan.agentName) wants to change your library",
            body: plan.summary,
            payload: ["planId": plan.id.uuidString.lowercased()]
        )
    }
}
