import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

/// OUT-004 · the user's side of remote approval. Session-only: `AuthMiddleware` resolves
/// sessions, never agent tokens, so no caller can approve its own plan.
extension APIImplementation {
    func listPlans(_ input: Operations.ListPlans.Input) async throws -> Operations.ListPlans.Output {
        let plans = try await services.plans.plans(userID: currentUser(), pendingOnly: input.query.status != .all)
        return .ok(.init(body: .json(.init(items: plans.map(Components.Schemas.AgentPlan.init)))))
    }

    func getPlan(_ input: Operations.GetPlan.Input) async throws -> Operations.GetPlan.Output {
        try await .ok(.init(body: .json(.init(services.plans.plan(planID(input.path.id), userID: currentUser())))))
    }

    func approvePlan(_ input: Operations.ApprovePlan.Input) async throws -> Operations.ApprovePlan.Output {
        let (plan, action) = try await services.plans.approve(planID(input.path.id), userID: currentUser())
        return .ok(.init(body: .json(.init(plan: .init(plan), action: .init(action)))))
    }

    func denyPlan(_ input: Operations.DenyPlan.Input) async throws -> Operations.DenyPlan.Output {
        try await .ok(.init(body: .json(.init(services.plans.deny(planID(input.path.id), userID: currentUser())))))
    }

    private func planID(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else { throw AppError.notFound("No such plan.") }
        return id
    }
}

extension Components.Schemas.AgentPlan {
    init(_ plan: AgentPlan) {
        self.init(
            id: plan.id.uuidString.lowercased(),
            status: .init(rawValue: plan.status.rawValue) ?? .expired,
            agentName: plan.agentName,
            summary: plan.summary,
            changes: plan.changes.map { change in
                .init(
                    text: change.text, titleId: change.titleID.description, title: change.title,
                    _type: .init(change.type), posterUrl: change.posterURL,
                    libraryItemId: change.libraryItemID?.description
                )
            },
            counts: .init(
                adds: plan.counts.adds, updates: plan.counts.updates, removes: plan.counts.removes,
                episodes: plan.counts.episodes
            ),
            createdAt: plan.createdAt,
            expiresAt: plan.expiresAt,
            decidedAt: plan.decidedAt,
            actionId: plan.actionID?.uuidString.lowercased()
        )
    }
}
