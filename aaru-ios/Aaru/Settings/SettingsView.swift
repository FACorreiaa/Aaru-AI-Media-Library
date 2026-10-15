import AaruAPI
import SwiftUI
import UniformTypeIdentifiers

/// APP-007: account, imports, and the way out (sign out, delete account).
struct SettingsView: View {
    let api: Client?
    let imports: ImportsModel
    let library: LibraryModel
    let lists: ListsModel
    var onSignOut: () -> Void
    var onDeleteAccount: () async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var account: Components.Schemas.Me?
    @State private var pickingFor: ImportFileSource?
    @State private var uploading = false
    @State private var confirmsDelete = false
    @State private var deleteProblem: String?
    @State private var openedJob: ImportJob?

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                importSection
                if !imports.jobs.isEmpty {
                    jobsSection
                }
                deleteSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(.paper))
            .safeAreaInset(edge: .bottom) { ProblemBanner(message: imports.problem) { imports.problem = nil } }
            .overlay {
                if uploading {
                    ProgressView("Uploading…").padding().background(
                        .regularMaterial,
                        in: .rect(cornerRadius: 14)
                    )
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: String.self) { id in
                ImportDetailView(id: id, imports: imports, library: library, lists: lists, api: api)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(
                isPresented: Binding(get: { pickingFor != nil }, set: {
                    if !$0 {
                        pickingFor = nil
                    }
                }),
                allowedContentTypes: [.commaSeparatedText, .plainText, .text]
            ) { result in
                guard let source = pickingFor else { return }
                pickingFor = nil
                if case let .success(url) = result {
                    Task { await upload(url, source: source) }
                }
            }
            .confirmationDialog(
                "Delete your Aaru account?",
                isPresented: $confirmsDelete,
                titleVisibility: .visible
            ) {
                Button("Delete account and library", role: .destructive) {
                    Task { deleteProblem = await onDeleteAccount() }
                }
            } message: {
                Text("This cannot be undone. Export first if you want to keep anything.")
            }
            .task {
                await imports.load()
                if let api, case let .ok(response) = try? await api.getMe() {
                    account = try? response.body.json
                }
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("Name", value: account?.displayName ?? "Not set")
            LabeledContent("Signed in with", value: providers)
            Button("Sign out", action: onSignOut)
        }
    }

    private var importSection: some View {
        Section {
            ForEach(ImportFileSource.allCases) { source in
                Button {
                    pickingFor = source
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from \(source.label)").foregroundStyle(Color(.ink))
                        Text(source.hint).font(.caption).foregroundStyle(Color(.muted))
                    }
                }
                .disabled(uploading)
            }
        } header: {
            Text("Bring your history")
        } footer: {
            Text(
                "Aaru matches every row first and shows you the plan. Nothing changes until you "
                    + "approve it, and an import undoes in one step."
            )
        }
    }

    private var jobsSection: some View {
        Section("Imports") {
            ForEach(imports.jobs, id: \.id) { job in
                NavigationLink(value: job.id) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.filename ?? job.sourceLabel).lineLimit(1)
                        Text("\(job.sourceLabel) · \(job.stateLabel)")
                            .font(.caption)
                            .foregroundStyle(job.state == .failed ? .red : Color(.muted))
                    }
                }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete account", role: .destructive) { confirmsDelete = true }
            if let deleteProblem {
                Text(deleteProblem).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text("Deletes your library, lists, imports and sessions from Aaru for good.")
        }
    }

    private var providers: String {
        let names = (account?.providers ?? []).map { provider in
            switch provider {
            case .apple: "Apple"
            case .google: "Google"
            case .email: "Email"
            }
        }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private func upload(_ url: URL, source: ImportFileSource) async {
        uploading = true
        defer { uploading = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url) else {
            imports.problem = "That file could not be read."
            return
        }
        _ = await imports.upload(data, filename: url.lastPathComponent, source: source)
    }
}

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
