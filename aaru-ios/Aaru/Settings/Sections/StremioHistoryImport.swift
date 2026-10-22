import AaruAPI
import SwiftUI

/// IMP-016: brings in what was watched in Stremio before the addon was installed. The user
/// approves a code on stremio.com; the server reads the library once, logs out, and plans an
/// import that waits for approval like any other.
struct StremioHistoryImport: View {
    let imports: ImportsModel
    var onImported: (ImportJob) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var link: Components.Schemas.StremioLink?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let link {
                    waiting(link)
                } else if failed {
                    ContentUnavailableView {
                        Label("Stremio did not answer", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(imports.problem ?? "Try again in a minute.")
                    } actions: {
                        Button("Try again") { Task { await start() } }
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.paper))
            .navigationTitle("Import from Stremio")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task { await start() }
    }

    private func waiting(_ link: Components.Schemas.StremioLink) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Sign in to Stremio and approve this code. Your Stremio password never reaches Aaru.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(.muted))
                Text(link.code)
                    .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(Color(.ink))
                    .accessibilityLabel("Code \(link.code.map(String.init).joined(separator: " "))")
                if let page = URL(string: link.link) {
                    Link(destination: page) {
                        Label("Approve on stremio.com", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                if let qrImage = URL(string: link.qrcode) {
                    AsyncImage(url: qrImage) { image in
                        image.resizable().interpolation(.none).scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 160, height: 160)
                    .padding(6)
                    .background(.white, in: .rect(cornerRadius: 10))
                    .accessibilityLabel("QR code that opens the Stremio approval page on another device")
                }
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for approval…").foregroundStyle(Color(.muted))
                }
                .font(.footnote)
            }
            .padding(24)
        }
        .task(id: link.code) { await poll(link.code) }
    }

    private func start() async {
        failed = false
        link = await imports.startStremioImport()
        failed = link == nil
    }

    /// Asks every 3 s until approved; stops when the sheet closes (the task is cancelled).
    private func poll(_ code: String) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            switch await imports.pollStremioImport(code: code) {
            case .pending:
                continue
            case let .imported(job):
                dismiss()
                onImported(job)
                return
            case .failed:
                link = nil
                failed = true
                return
            }
        }
    }
}
