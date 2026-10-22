import SwiftUI
import UniformTypeIdentifiers

/// IMP-009/010: Pogdesign CAT has no list export, so its shows come in three ways: the iCal link,
/// the iCal file, or a pasted list. Only shows come across; CAT's watched episodes do not.
struct CATImportSheet: View {
    let imports: ImportsModel
    var onImported: (ImportJob) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var list = ""
    @State private var picksFile = false
    @State private var busy = false

    var body: some View {
        @Bindable var imports = imports
        NavigationStack {
            Form {
                Section {
                    TextField("https://www.pogdesign.co.uk/cat/download_ics/…", text: $link)
                        .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                    Button("Import from link") { run { await imports.importCATLink(link) } }
                        .disabled(busy || link.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Your CAT iCal link")
                } footer: {
                    Text(
                        "In CAT, signed in: copy the “Download iCal File” link. Aaru reads it once and doesn't keep it."
                    )
                }
                Section {
                    TextEditor(text: $list)
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                    Button("Import list") { run { await imports.importCAT(list) } }
                        .disabled(busy || list.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Choose the .ics file") { picksFile = true }
                        .disabled(busy)
                } header: {
                    Text("Or paste your shows, one per line")
                } footer: {
                    Text("Your shows arrive as Plan to watch. CAT's watched episodes don't come across.")
                }
            }
            .settingsPage("Pogdesign CAT", problem: $imports.problem)
            .overlay {
                if busy {
                    ProgressView("Starting…").padding().background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .fileImporter(
                isPresented: $picksFile,
                allowedContentTypes: [UTType(filenameExtension: "ics") ?? .calendarEvent, .calendarEvent, .plainText]
            ) { result in
                guard case let .success(url) = result else { return }
                run { await importFile(url) }
            }
        }
    }

    private func run(_ start: @escaping () async -> ImportJob?) {
        busy = true
        Task {
            let job = await start()
            busy = false
            if let job {
                dismiss()
                onImported(job)
            }
        }
    }

    private func importFile(_ url: URL) async -> ImportJob? {
        await imports.importCATFile(at: url)
    }
}
