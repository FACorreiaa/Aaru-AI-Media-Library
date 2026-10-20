import AaruAPI
import SwiftUI

/// One import: progress while it is matched, then the plan to approve, then what happened.
struct ImportDetailView: View {
    let id: String
    let imports: ImportsModel
    let library: LibraryModel
    let lists: ListsModel
    let api: Client?

    @State private var detail: ImportDetail?
    @State private var applying = false
    @Environment(\.dismiss) private var dismiss

    private var job: ImportJob? {
        detail?.job
    }

    var body: some View {
        Form {
            if let job {
                Section {
                    LabeledContent("Status", value: job.stateLabel)
                    if job.isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if let error = job.errorSummary, job.state == .failed {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                if !job.isWorking, job.state != .failed {
                    Section(job.state == .planned ? "The plan" : "Result") {
                        LabeledContent(
                            job.state == .planned ? "New on your shelf" : "Added",
                            value: "\(job.stats.created)"
                        )
                        LabeledContent(job.state == .planned ? "Filled in" : "Updated", value: "\(job.stats.updated)")
                        LabeledContent("Already there", value: "\(job.stats.skipped)")
                        LabeledContent("Not matched", value: "\(job.stats.unmatched)")
                    }
                }
                if job.state == .planned {
                    Section {
                        Button(applying ? "Importing…" : "Approve and import") { Task { await apply() } }
                            .disabled(applying)
                        Button("Discard", role: .destructive) {
                            Task {
                                if await imports.discard(id) {
                                    dismiss()
                                }
                            }
                        }
                    } footer: {
                        Text("One step to undo: it lands in your history as a single action.")
                    }
                }
                rows(.unmatched, title: "Not matched")
                rows(.create, title: job.state == .planned ? "Will be added" : "Added")
                rows(.update, title: job.state == .planned ? "Will be filled in" : "Filled in")
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .safeAreaInset(edge: .bottom) { ProblemBanner(message: imports.problem) { imports.problem = nil } }
        .navigationTitle(job?.filename ?? job?.sourceLabel ?? "Import")
        .task(id: id) { await poll() }
    }

    @ViewBuilder
    private func rows(_ outcome: Components.Schemas.ImportRow.OutcomePayload, title: String) -> some View {
        let matching = detail?.rows.filter { $0.outcome == outcome } ?? []
        if !matching.isEmpty {
            Section("\(title) (\(matching.count))") {
                ForEach(matching.prefix(200), id: \.index) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text([row.title, row.year.map { "(\($0))" }].compactMap(\.self).joined(separator: " "))
                        if let reason = row.reason {
                            Text(reason).font(.caption).foregroundStyle(Color(.muted))
                        }
                    }
                }
            }
        }
    }

    /// Polls every two seconds while the server is still matching ("live-ish" progress).
    private func poll() async {
        while !Task.isCancelled {
            detail = await imports.detail(id)
            guard detail?.job.isWorking == true else { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func apply() async {
        applying = true
        defer { applying = false }
        if await imports.apply(id) != nil {
            detail = await imports.detail(id)
            await library.sync(api: api)
            await lists.load()
        }
    }
}
