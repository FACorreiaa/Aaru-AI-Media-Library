import SwiftUI
import UniformTypeIdentifiers

/// Settings → Import (§18): Trakt, then "Bring your history" in `CLAUDE.md`'s import order
/// (UX-026), then the jobs so far ("No imports yet." when none, UX-034). Export is on Your data.
struct ImportPage: View {
    let imports: ImportsModel
    /// Opens an import job's plan.
    var openJob: (String) -> Void

    @State private var pickingFor: ImportFileSource?
    @State private var asksAniListName = false
    @State private var aniListName = ""
    @State private var showsCAT = false
    @State private var showsStremio = false

    var body: some View {
        @Bindable var imports = imports
        Form {
            TraktSection(imports: imports) { openJob($0.id) }
            HistorySourcesSection(busy: imports.uploading, choose: choose)
            ImportJobsSection(imports: imports)
        }
        .settingsPage("Import", problem: $imports.problem)
        .overlay {
            if imports.uploading {
                ProgressView("Uploading…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: AaruRadius.panel, style: .continuous))
            }
        }
        .fileImporter(
            isPresented: $pickingFor.isPresent,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text, .xml, .gzip]
        ) { result in
            guard let source = pickingFor else { return }
            pickingFor = nil
            if case let .success(url) = result {
                Task { await upload(url, source: source) }
            }
        }
        .sheet(isPresented: $showsCAT) {
            CATImportSheet(imports: imports) { openJob($0.id) }
        }
        .sheet(isPresented: $showsStremio) {
            StremioHistoryImport(imports: imports) { openJob($0.id) }
        }
        .alert("Import from AniList", isPresented: $asksAniListName) {
            TextField("Username", text: $aniListName)
                .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
            Button("Import") { Task { await importAniList() } }
                .disabled(aniListName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your AniList anime list must be public.")
        }
        .task { await imports.load() }
    }

    private func choose(_ source: HistorySource) {
        switch source {
        case .stremio: showsStremio = true
        case let .file(file): pickingFor = file
        case .cat: showsCAT = true
        case .aniList:
            aniListName = ""
            asksAniListName = true
        }
    }

    private func upload(_ url: URL, source: ImportFileSource) async {
        if let job = await imports.upload(fileAt: url, source: source) {
            openJob(job.id)
        }
    }

    private func importAniList() async {
        let name = aniListName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let job = await imports.importAniList(username: name) {
            openJob(job.id)
        }
    }
}

/// "Bring your history": one row per source, in the import order.
private struct HistorySourcesSection: View {
    let busy: Bool
    var choose: (HistorySource) -> Void

    var body: some View {
        Section {
            ForEach(HistorySource.ordered) { source in
                Button {
                    choose(source)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title).foregroundStyle(Color(.ink))
                        Text(source.hint).font(.caption).foregroundStyle(Color(.muted))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityHint("Imports from \(source.title)")
            }
        } header: {
            Text("Bring your history")
        } footer: {
            Text(
                "Aaru matches every row first and shows you the plan. Nothing changes until you approve it, "
                    + "and an import undoes in one step from History, in Your data."
            )
        }
    }
}

/// The imports so far, newest first, each opening its plan or result.
private struct ImportJobsSection: View {
    let imports: ImportsModel

    var body: some View {
        Section("Imports") {
            if imports.jobs.isEmpty {
                Text(imports.hasLoaded ? "No imports yet." : "Loading your imports…")
                    .foregroundStyle(Color(.muted))
            }
            ForEach(imports.jobs, id: \.id) { job in
                NavigationLink(value: SettingsRoute.job(job.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.filename ?? job.sourceLabel).lineLimit(2)
                        Text("\(job.sourceLabel) · \(job.stateLabel)")
                            .font(.caption)
                            .foregroundStyle(job.state == .failed ? Color(.danger) : Color(.muted))
                    }
                }
            }
        }
    }
}
