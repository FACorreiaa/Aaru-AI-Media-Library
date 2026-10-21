import AaruAPI
import SwiftUI

typealias AgentPlan = Components.Schemas.AgentPlan

/// DESIGN §12: an outside agent's request. Who asked leads, then what changes, then the two
/// answers. Nothing is written until Approve; approval is one action the history can undo.
struct PlanCardView: View {
    let api: Client
    @State var plan: AgentPlan
    /// Called once the user decided, with the plan as the server left it.
    var onDecided: (AgentPlan) -> Void = { _ in }

    @State private var working = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(plan.agentName) asks")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color(.muted))
            Text(plan.summary)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color(.ink))
            Text("\(Self.counts(plan)) · nothing changes until you approve")
                .font(.footnote)
                .foregroundStyle(Color(.muted))
            if plan.changes.count > 1 {
                ForEach(Array(plan.changes.enumerated()), id: \.offset) { _, change in
                    Text(change.text).font(.footnote).lineLimit(1)
                }
            }
            if let decided = Self.decided(plan) {
                Text(decided).font(.callout.weight(.medium))
            } else {
                HStack {
                    Button("Approve") { Task { await decide(approve: true) } }
                        .buttonStyle(.borderedProminent)
                    Button("Not this") { Task { await decide(approve: false) } }
                        .buttonStyle(.bordered)
                }
                .disabled(working)
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.surface), in: RoundedRectangle(cornerRadius: 20))
    }

    private func decide(approve: Bool) async {
        working = true
        problem = nil
        defer { working = false }
        let path = Operations.ApprovePlan.Input.Path(id: plan.id)
        do {
            if approve {
                switch try await api.approvePlan(path: path) {
                case let .ok(response):
                    plan = try response.body.json.plan
                    onDecided(plan)
                case let .default(_, error):
                    problem = (try? error.body.json.message) ?? "Nothing was changed."
                }
            } else {
                switch try await api.denyPlan(path: .init(id: plan.id)) {
                case let .ok(response):
                    plan = try response.body.json
                    onDecided(plan)
                case let .default(_, error):
                    problem = (try? error.body.json.message) ?? "Nothing was changed."
                }
            }
        } catch {
            problem = "Aaru could not reach the server. Nothing was changed."
        }
    }

    static func counts(_ plan: AgentPlan) -> String {
        let counts = plan.counts
        func plural(_ count: Int, _ noun: String) -> String {
            "\(count) \(noun)\(count == 1 ? "" : "s")"
        }
        return [
            counts.episodes > 0 ? plural(counts.episodes, "episode") : nil,
            counts.adds > 0 ? "\(plural(counts.adds, "title")) added" : nil,
            counts.updates > 0 ? "\(plural(counts.updates, "item")) updated" : nil,
            counts.removes > 0 ? "\(plural(counts.removes, "title")) removed" : nil,
        ].compactMap(\.self).joined(separator: " · ")
    }

    static func decided(_ plan: AgentPlan) -> String? {
        switch plan.status {
        case .pending: nil
        case .applied: "Applied. You can undo it from your history."
        case .denied: "You said no. Nothing changed."
        case .stale: "Your library changed since, so nothing was applied."
        case .expired: "Expired. Nothing changed."
        }
    }
}

/// Where a plan's push notification opens: the plan, loaded by id.
struct PlanSheet: View {
    let api: Client
    let id: String
    var onDone: () -> Void

    @State private var plan: AgentPlan?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Group {
                if let plan {
                    ScrollView { PlanCardView(api: api, plan: plan).padding(16) }
                } else if let problem {
                    ContentUnavailableView(
                        "Request unavailable",
                        systemImage: "questionmark",
                        description: Text(problem)
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Request")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            }
            .task { await load() }
        }
    }

    private func load() async {
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
}
