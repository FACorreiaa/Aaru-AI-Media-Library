import AaruAPI
import SwiftUI

/// One import: progress while it is matched, then the plan to approve, then what happened. An
/// unmatched row can be found by hand (IMP-011), before or after the plan is approved.
struct ImportDetailView: View {
    let id: String
    let imports: ImportsModel
    /// For "Find it" (IMP-011): the catalog search over this library and these lists.
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    /// After the plan is applied, or a row found by hand after it: the library and lists catch up.
    var onApplied: @MainActor () async -> Void

    @State private var detail: ImportDetail?
    @State private var applying = false
    /// The unmatched row being found in search.
    @State private var finding: ImportRow?
    @State private var confirmsDiscard = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    /// Nil in previews.
    @Environment(ToastCenter.self) private var toasts: ToastCenter?

    /// From Home's last-import card, outside Settings.
    init(id: String, imports: ImportsModel, library: LibraryModel, lists: ListsModel, api: Client?) {
        self.id = id
        self.imports = imports
        self.api = api
        self.library = library
        self.lists = lists
        onApplied = {
            await library.sync(api: api)
            await lists.load()
        }
    }

    init(id: String, context: SettingsContext) {
        self.id = id
        imports = context.imports
        api = context.api
        library = context.library
        lists = context.lists
        onApplied = { await context.refreshLibrary() }
    }

    private var job: ImportJob? {
        detail?.job
    }

    var body: some View {
        Form {
            if let job {
                Section {
                    LabeledContent("Status", value: job.stateLabel)
                    if let error = job.errorSummary, job.state == .failed {
                        Text(error).font(.footnote).foregroundStyle(Color(.danger))
                    }
                    if job.state == .failed {
                        // UX-078: a failed import can be cleared away, back to Import.
                        Button("Remove this import", role: .destructive) { Task { await discard() } }
                    }
                }
                if job.isWorking {
                    Section {
                        ImportLedger(steps: job.steps)
                        if job.state == .queued {
                            Button("Cancel this import", role: .destructive) { Task { await discard() } }
                        }
                    } footer: {
                        Text(
                            "You can leave: the plan waits under Settings → Import, and nothing reaches your "
                                + "library until you approve it."
                        )
                    }
                }
                if !job.isWorking, job.state != .failed {
                    Section(job.state == .planned ? "The plan" : "Result") {
                        LabeledContent(
                            job.state == .planned ? "New in your library" : "Added",
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
                        Button("Discard", role: .destructive) { confirmsDiscard = true }
                    } footer: {
                        Text("One step to undo: it lands in History, in Your data, as a single action.")
                    }
                }
                if job.state == .succeeded || job.state == .partial {
                    Section {
                        Button("See it in History", systemImage: "clock.arrow.circlepath") { router.openHistory() }
                    } footer: {
                        Text("Undo the whole import there in one step.")
                    }
                }
                rows(.unmatched, title: "Not matched")
                rows(.create, title: job.state == .planned ? "Will be added" : "Added")
                rows(.update, title: job.state == .planned ? "Will be filled in" : "Filled in")
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .settingsPage(job?.filename ?? job?.sourceLabel ?? "Import", problem: problem)
        .undoToast()
        .confirmationDialog("Discard this plan?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { Task { await discard() } }
        } message: {
            Text("Nothing was added yet. You can import the file again later.")
        }
        .task(id: id) { await poll() }
        .sheet(item: $finding) { row in
            SearchView(api: api, library: library, lists: lists, pick: pick(for: row))
        }
    }

    /// Rows can be found by hand once matching is over: into the plan, or straight into the library.
    private var canFind: Bool {
        guard let job else { return false }
        return !job.isWorking && job.state != .failed
    }

    private var problem: Binding<String?> {
        Binding(get: { imports.problem }, set: { imports.problem = $0 })
    }

    /// Rows shown per outcome; the rest are counted (UX-078).
    private static let shownRows = 200

    @ViewBuilder
    private func rows(_ outcome: Components.Schemas.ImportRow.OutcomePayload, title: String) -> some View {
        let matching = detail?.rows.filter { $0.outcome == outcome } ?? []
        let findable = outcome == .unmatched && canFind
        if !matching.isEmpty {
            Section {
                ForEach(matching.prefix(Self.shownRows), id: \.index) { row in
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
                                .frame(minHeight: 44)
                                .accessibilityLabel("Find \(row.title)")
                        }
                    }
                }
            } header: {
                Text("\(title) (\(matching.count.formatted()))")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if findable {
                        Text(
                            job?.state == .planned
                                ? "Find it searches the catalog. The title you choose joins the plan."
                                : "Find it searches the catalog. The title you choose goes in your library at "
                                + "once, and can be undone from History."
                        )
                    }
                    if matching.count > Self.shownRows {
                        Text("Showing \(Self.shownRows) of \(matching.count.formatted()).")
                    }
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
    /// to the library, so the library catches up behind the closing sheet.
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
            Task { await onApplied() }
        }
        return nil
    }

    private func discard() async {
        if await imports.discard(id) {
            dismiss()
        }
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

    /// The whole import is one action, so the toast that follows offers Undo (DESIGN.md §9).
    private func apply() async {
        applying = true
        defer { applying = false }
        guard let applied = await imports.apply(id) else { return }
        detail = await imports.detail(id)
        await onApplied()
        guard let actionID = applied.actionId, let api else { return }
        toasts?.show(Self.appliedMessage(applied.stats)) {
            let problem = await api.takeBack(actionID: actionID)
            if problem == nil {
                detail = await imports.detail(id)
                await onApplied()
            }
            return problem
        }
    }

    /// "Imported 12 titles", "Imported 12 titles · filled in 3".
    static func appliedMessage(_ stats: Components.Schemas.ImportStats) -> String {
        let added = stats.created == 1 ? "Imported 1 title" : "Imported \(stats.created) titles"
        return stats.updated > 0 ? "\(added) · filled in \(stats.updated)" : added
    }
}

private extension ImportRow {
    /// "Dune (2021)": the name as the import file had it.
    var label: String {
        [title, year.map { "(\($0))" }].compactMap(\.self).joined(separator: " ")
    }
}
