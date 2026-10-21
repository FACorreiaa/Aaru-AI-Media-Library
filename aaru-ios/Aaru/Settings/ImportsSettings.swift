import AaruAPI
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Imports & export: Trakt, the file sources, AniList, CAT and Stremio history, the
/// jobs so far, and the way out.
struct ImportsSettings: View {
    let api: Client?
    let imports: ImportsModel
    /// Opens an import job's plan.
    var openJob: (String) -> Void

    @State private var pickingFor: ImportFileSource?
    @State private var uploading = false
    @State private var asksAniListName = false
    @State private var aniListName = ""
    @State private var showsCAT = false
    @State private var showsStremio = false

    var body: some View {
        Form {
            TraktSection(api: api) { imports.problem = $0 } onImported: { openJob($0.id) }
            historySection
            if !imports.jobs.isEmpty {
                jobsSection
            }
            ExportDataSection(api: api) { imports.problem = $0 }
        }
        .settingsForm(imports)
        .overlay {
            if uploading {
                ProgressView("Uploading…").padding().background(
                    .regularMaterial,
                    in: .rect(cornerRadius: 14)
                )
            }
        }
        .navigationTitle("Imports & export")
        .fileImporter(
            isPresented: Binding(get: { pickingFor != nil }, set: {
                if !$0 {
                    pickingFor = nil
                }
            }),
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

    private var historySection: some View {
        Section {
            ForEach(ImportFileSource.offered) { source in
                Button {
                    pickingFor = source
                } label: {
                    sourceLabel("Import from \(source.label)", hint: source.hint)
                }
                .disabled(uploading)
            }
            Button {
                aniListName = ""
                asksAniListName = true
            } label: {
                sourceLabel("Import from AniList", hint: "Your public anime list, by username.")
            }
            .disabled(uploading)
            Button {
                showsCAT = true
            } label: {
                sourceLabel("Import from Pogdesign CAT", hint: "Your iCal link or file, or a list of shows.")
            }
            .disabled(uploading)
            Button {
                showsStremio = true
            } label: {
                sourceLabel("Import from Stremio", hint: "What you watched before, approved on stremio.com.")
            }
            .disabled(uploading || api == nil)
        } header: {
            Text("Bring your history")
        } footer: {
            Text(
                "Aaru matches every row first and shows you the plan. Nothing changes until you "
                    + "approve it, and an import undoes in one step."
            )
        }
    }

    private func sourceLabel(_ title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Color(.ink))
            Text(hint).font(.caption).foregroundStyle(Color(.muted))
        }
    }

    private var jobsSection: some View {
        Section("Imports") {
            ForEach(imports.jobs, id: \.id) { job in
                NavigationLink(value: SettingsRoute.job(job.id)) {
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

    private func upload(_ url: URL, source: ImportFileSource) async {
        uploading = true
        defer { uploading = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard var data = try? Data(contentsOf: url) else {
            imports.problem = "That file could not be read."
            return
        }
        var filename = url.lastPathComponent
        // MyAnimeList's export downloads gzipped; the server takes the XML inside.
        if Gunzip.isGzip(data) {
            do {
                data = try Gunzip.decompress(data, limit: Self.maxUploadBytes)
                filename = filename.hasSuffix(".gz") ? String(filename.dropLast(3)) : filename
            } catch Gunzip.Failure.tooLarge {
                imports.problem = "That file is larger than 5 MB unpacked. Check it is the right export."
                return
            } catch {
                imports.problem = "That file could not be unpacked. Upload the .xml file instead."
                return
            }
        }
        _ = await imports.upload(data, filename: filename, source: source)
    }

    /// The server's upload limit (`ImportService.maxUploadBytes`).
    private static let maxUploadBytes = 5 * 1024 * 1024

    private func importAniList() async {
        let name = aniListName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let job = await imports.importAniList(username: name) {
            openJob(job.id)
        }
    }
}
