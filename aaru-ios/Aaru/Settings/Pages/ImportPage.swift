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
    /// Last.fm or ListenBrainz, while its username is asked (MUS-004).
    @State private var listenAccount: HistorySource?
    @State private var listenName = ""

    var body: some View {
        @Bindable var imports = imports
        Form {
            TraktSection(imports: imports) { openJob($0.id) }
            HistorySourcesSection(
                title: "Bring your history", sources: HistorySource.ordered, busy: imports.uploading, choose: choose,
                footer: "Aaru matches every row first and shows you the plan. Nothing changes until you approve it, "
                    + "and an import undoes in one step from History, in Your data."
            )
            HistorySourcesSection(
                title: "Music history", sources: HistorySource.music, busy: imports.uploading, choose: choose,
                footer: "Past listening goes to your Music log, never your library. Each listen counts on the day "
                    + "you played it, and an import undoes in one step."
            )
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
            allowedContentTypes: pickingFor?.isListening == true
                ? [.json] : [.commaSeparatedText, .plainText, .text, .xml, .gzip]
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
        .alert(
            "Import from \(listenAccount?.title ?? "")",
            isPresented: Binding(get: { listenAccount != nil }, set: {
                if !$0 {
                    listenAccount = nil
                }
            }),
            presenting: listenAccount
        ) { source in
            TextField("Username", text: $listenName)
                .autocorrectionDisabled()
            #if os(iOS)
                .textInputAutocapitalization(.never)
            #endif
            Button("Import") { Task { await importListens(from: source) } }
                .disabled(listenName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: { source in
            Text(
                source == .lastFM ? "Your recent listening must not be hidden on Last.fm."
                    : "Your listens on ListenBrainz are public."
            )
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
        case .lastFM, .listenBrainz:
            listenName = ""
            listenAccount = source
        }
    }

    private func importListens(from source: HistorySource) async {
        let name = listenName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let job = await imports.importListens(from: source, username: name) {
            openJob(job.id)
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

/// "Bring your history" (one row per source, in the import order) and "Music history".
private struct HistorySourcesSection: View {
    let title: String
    let sources: [HistorySource]
    let busy: Bool
    var choose: (HistorySource) -> Void
    let footer: String

    var body: some View {
        Section {
            ForEach(sources) { source in
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
            Text(title)
        } footer: {
            Text(footer)
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
