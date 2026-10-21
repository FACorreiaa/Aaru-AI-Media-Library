import AaruAPI
import SwiftUI
import UniformTypeIdentifiers

/// APP-007: account, imports, and the way out (sign out, delete account). A tab of its own, and
/// the Settings window (Cmd-,) on Mac.
struct SettingsView: View {
    let api: Client?
    let imports: ImportsModel
    let library: LibraryModel
    let lists: ListsModel
    var onSignOut: () -> Void
    var onDeleteAccount: () async -> String?
    /// A sheet needs a way out; the Settings tab and the Mac Settings window do not.
    var showsDone = false

    @Environment(\.dismiss) private var dismiss
    @State private var account: Components.Schemas.Me?
    @State private var pickingFor: ImportFileSource?
    @State private var uploading = false
    @State private var confirmsDelete = false
    @State private var deleteProblem: String?
    @State private var openedJob: ImportJob?
    @State private var path: [String] = []
    @State private var asksAniListName = false
    @State private var aniListName = ""
    @State private var showsCAT = false

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                accountSection
                #if os(iOS)
                    if let push = PushRegistrar.current {
                        NotificationsSection(push: push)
                    }
                #endif
                importSection
                if !imports.jobs.isEmpty {
                    jobsSection
                }
                StremioSection(api: api, imports: imports) { imports.problem = $0 } onImported: { job in
                    path.append(job.id)
                }
                ConnectionsSection(api: api) { imports.problem = $0 }
                ExportDataSection(api: api) { imports.problem = $0 }
                Section {
                    NavigationLink("About Aaru") { AboutView() }
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
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
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
                CATImportSheet(imports: imports) { path.append($0.id) }
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
            .confirmationDialog(
                "Delete your Aaru account?",
                isPresented: $confirmsDelete,
                titleVisibility: .visible
            ) {
                Button("Delete account and library", role: .destructive) {
                    Task { deleteProblem = await onDeleteAccount() }
                }
            } message: {
                Text("This cannot be undone. Export your data first if you want to keep it.")
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
            if let clientID = AppEnvironment.googleClientID, let account, !account.providers.contains(.google) {
                LinkGoogleButton(api: api, clientID: clientID, account: $account)
            }
            Button("Sign out", action: onSignOut)
        }
    }

    private var importSection: some View {
        Section {
            ForEach(ImportFileSource.offered) { source in
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
            Button {
                aniListName = ""
                asksAniListName = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from AniList").foregroundStyle(Color(.ink))
                    Text("Your public anime list, by username.").font(.caption).foregroundStyle(Color(.muted))
                }
            }
            .disabled(uploading)
            Button {
                showsCAT = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from Pogdesign CAT").foregroundStyle(Color(.ink))
                    Text("Your iCal link or file, or a list of shows.").font(.caption).foregroundStyle(Color(.muted))
                }
            }
            .disabled(uploading)
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
            path.append(job.id)
        }
    }
}

#if os(iOS)
    /// Airing alerts: a new episode of a show you are watching.
    private struct NotificationsSection: View {
        let push: PushRegistrar

        var body: some View {
            Section {
                Toggle(
                    "New episodes",
                    isOn: Binding(get: { push.airing }, set: { value in Task { await push.setAiring(value) } })
                )
                if let problem = push.problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("A notification when a new episode of a show you are watching comes out.")
            }
            .task { await push.loadSetting() }
        }
    }
#endif
