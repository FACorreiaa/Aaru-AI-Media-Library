import AaruAPI
import SwiftUI

typealias AgentPlan = Components.Schemas.AgentPlan

/// DESIGN §12: an outside agent's request. Who asked leads, then what changes, then the two
/// answers. Nothing is written until Approve; approval is one action History can undo, and an
/// applied request links there (UX-060).
struct PlanCardView: View {
    /// Called once the user decided, with the plan as the server left it.
    var onDecided: (AgentPlan) -> Void
    /// Opens History. Nil: the router's, from where the card is; a sheet passes its own, which
    /// closes the sheet first.
    var onShowHistory: (() -> Void)?

    @State private var model: PlanModel
    @Environment(AppRouter.self) private var router

    init(
        api: Client,
        plan: AgentPlan,
        onShowHistory: (() -> Void)? = nil,
        onDecided: @escaping (AgentPlan) -> Void = { _ in }
    ) {
        self.onDecided = onDecided
        self.onShowHistory = onShowHistory
        _model = State(initialValue: PlanModel(api: api, plan: plan))
    }

    var body: some View {
        if let plan = model.plan {
            card(plan)
        }
    }

    private func card(_ plan: AgentPlan) -> some View {
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
                if plan.status == .applied {
                    Button("Open History", systemImage: "clock.arrow.circlepath") {
                        if let onShowHistory {
                            onShowHistory()
                        } else {
                            router.openHistory()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack {
                    Button("Approve") { decide(approve: true) }
                        .buttonStyle(.borderedProminent)
                    Button("Not this") { decide(approve: false) }
                        .buttonStyle(.bordered)
                }
                .disabled(model.working)
            }
            if let problem = model.problem {
                Text(problem).font(.footnote).foregroundStyle(Color(.danger))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.surface), in: RoundedRectangle(cornerRadius: 20))
    }

    private func decide(approve: Bool) {
        Task {
            if let decided = await model.decide(approve: approve) {
                onDecided(decided)
            }
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
        case .applied: "Applied. You can undo it from History."
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

    @State private var model: PlanModel
    @Environment(AppRouter.self) private var router

    init(api: Client, id: String, onDone: @escaping () -> Void) {
        self.api = api
        self.id = id
        self.onDone = onDone
        _model = State(initialValue: PlanModel(api: api))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let plan = model.plan {
                    ScrollView {
                        PlanCardView(api: api, plan: plan, onShowHistory: showHistory).padding(16)
                    }
                } else if let problem = model.problem {
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
            .task { await model.load(id: id) }
        }
    }

    /// Closes this sheet, then opens History once it is gone: on iPhone History is in a sheet too.
    private func showHistory() {
        onDone()
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            router.openHistory()
        }
    }
}
