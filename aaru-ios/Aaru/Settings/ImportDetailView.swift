import AaruAPI
import SwiftUI

/// One import: progress while it is matched, then the plan to approve, then what happened. An
/// unmatched row can be found by hand (IMP-011), before or after the plan is approved.
struct ImportDetailView: View {
    let id: String
    let imports: ImportsModel
    let library: LibraryModel
    let lists: ListsModel
    let api: Client?

    @State private var detail: ImportDetail?
    @State private var applying = false
    /// The unmatched row being found in search.
    @State private var finding: ImportRow?
    @Environment(\.dismiss) private var dismiss

    private var job: ImportJob? {
        detail?.job
    }

    var body: some View {
        Form {
            if let job {
                Section {
                    LabeledContent("Status", value: job.stateLabel)
                    if let error = job.errorSummary, job.state == .failed {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                if job.isWorking {
                    Section {
                        ImportLedger(steps: job.steps)
                        if job.state == .queued {
                            Button("Cancel this import", role: .destructive) {
                                Task {
                                    if await imports.discard(id) {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    } footer: {
                        Text(
                            "You can leave: the plan waits under Imports, and nothing reaches your shelf "
                                + "until you approve it."
                        )
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
        .sheet(item: $finding) { row in
            SearchView(api: api, library: library, lists: lists, pick: pick(for: row))
        }
    }

    /// Rows can be found by hand once matching is over: into the plan, or straight onto the shelf.
    private var canFind: Bool {
        guard let job else { return false }
        return !job.isWorking && job.state != .failed
    }

    @ViewBuilder
    private func rows(_ outcome: Components.Schemas.ImportRow.OutcomePayload, title: String) -> some View {
        let matching = detail?.rows.filter { $0.outcome == outcome } ?? []
        let findable = outcome == .unmatched && canFind
        if !matching.isEmpty {
            Section {
                ForEach(matching.prefix(200), id: \.index) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                            if let reason = row.reason {
                                Text(reason).font(.caption).foregroundStyle(Color(.muted))
                            }
                        }
                        if findable {
                            Spacer(minLength: 8)
                            Button("Find it") { finding = row }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Find \(row.title)")
                        }
                    }
                }
            } header: {
                Text("\(title) (\(matching.count))")
            } footer: {
                if findable {
                    Text(
                        job?.state == .planned
                            ? "Find it searches the catalog. The title you choose joins the plan."
                            : "Find it searches the catalog. The title you choose goes on your shelf at once, "
                            + "and can be undone from History."
                    )
                }
            }
        }
    }

    /// The search for one unmatched row: its name, in its kind. MAL and AniList rows are anime.
    private func pick(for row: ImportRow) -> SearchPick {
        let isAnime = job?.source == .malXml || job?.source == .anilist
            || row.ids?.anilist != nil || row.ids?.mal != nil
        let kind = MediaKind(type: row._type, isAnime: isAnime)
        return SearchPick(
            query: row.title,
            scope: SearchScope(rawValue: kind.rawValue) ?? .all,
            year: row.year,
            navigationTitle: "Find a title",
            note: "\u{201C}\(row.label)\u{201D} in your import. Choose the title it means.",
            choose: { hit in await resolve(row, with: hit) }
        )
    }

    /// Saves the pick and updates the row and the counts in place. After approval it was written
    /// to the shelf, so the library catches up behind the closing sheet.
    private func resolve(_ row: ImportRow, with hit: CatalogHit) async -> String? {
        guard let resolved = await imports.resolve(id, row: row.index, with: hit) else {
            defer { imports.problem = nil }
            return imports.problem ?? "\(hit.title) could not be matched to that row."
        }
        detail?.job = resolved.job
        if let position = detail?.rows.firstIndex(where: { $0.index == resolved.row.index }) {
            detail?.rows[position] = resolved.row
        }
        if resolved.job.state != .planned {
            Task {
                await library.sync(api: api)
                await lists.load()
            }
        }
        return nil
    }

    /// Polls every two seconds while the server is still matching. The job list carries the
    /// progress; the rows (thousands for a big export) are read once, when matching ends.
    private func poll() async {
        detail = await imports.detail(id)
        while !Task.isCancelled, detail?.job.isWorking == true {
            try? await Task.sleep(for: .seconds(2))
            guard let fresh = await imports.job(id) else { continue }
            if fresh.isWorking {
                detail?.job = fresh
            } else {
                detail = await imports.detail(id)
            }
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

private extension ImportRow {
    /// "Dune (2021)": the name as the import file had it.
    var label: String {
        [title, year.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
    }
}
