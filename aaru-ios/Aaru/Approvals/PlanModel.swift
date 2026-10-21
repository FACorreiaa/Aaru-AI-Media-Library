import AaruAPI
import Foundation
import Observation

extension Notification.Name {
    /// An agent request was approved or denied; the object is the `AgentPlan` as the server left
    /// it. Home's "Waiting for you" listens, wherever the answer was given (UX-082).
    static let aaruPlanDecided = Notification.Name("aaruPlanDecided")
}

/// One agent request (OUT-004): loaded by id for a notification's sheet, or given by Home's
/// list, then approved or denied.
@MainActor
@Observable
final class PlanModel {
    private(set) var plan: AgentPlan?
    private(set) var working = false
    var problem: String?

    @ObservationIgnored private let api: Client

    init(api: Client, plan: AgentPlan? = nil) {
        self.api = api
        self.plan = plan
    }

    func load(id: String) async {
        do {
            switch try await api.getPlan(path: .init(id: id)) {
            case let .ok(response):
                plan = try response.body.json
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "This request could not be loaded."
            }
        } catch {
            problem = "Aaru could not reach the server."
        }
    }

    /// Answers the request. Returns the plan as the server left it, or nil when nothing changed.
    func decide(approve: Bool) async -> AgentPlan? {
        guard let current = plan, !working else { return nil }
        working = true
        problem = nil
        defer { working = false }
        do {
            let decided: AgentPlan
            if approve {
                switch try await api.approvePlan(path: .init(id: current.id)) {
                case let .ok(response):
                    decided = try response.body.json.plan
                case let .default(_, error):
                    problem = (try? error.body.json.message) ?? "Nothing was changed."
                    return nil
                }
            } else {
                switch try await api.denyPlan(path: .init(id: current.id)) {
                case let .ok(response):
                    decided = try response.body.json
                case let .default(_, error):
                    problem = (try? error.body.json.message) ?? "Nothing was changed."
                    return nil
                }
            }
            plan = decided
            NotificationCenter.default.post(name: .aaruPlanDecided, object: decided)
            return decided
        } catch {
            problem = "Aaru could not reach the server. Nothing was changed."
            return nil
        }
    }
}
