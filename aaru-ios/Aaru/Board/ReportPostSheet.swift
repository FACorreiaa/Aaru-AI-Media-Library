import AaruAPI
import SwiftUI

/// Report a friend's post (BOARD-003), a group message or a person: why, from four reasons, and an optional
/// note. It goes to Aaru through the user-report route with the post or message named; the author
/// is not told.
struct ReportPostSheet: View {
    typealias Reason = Components.Schemas.ReportCreate.ReasonPayload

    /// "post", "message" or "person": what the title says is being reported.
    let noun: String
    let authorName: String
    /// Sends the report. Returns what went wrong, or nil when it was sent.
    let report: (Reason, String?) async -> String?

    /// What the note may hold: the server takes 1,000 characters and the post's id goes first.
    private static let noteLimit = 900

    @Environment(\.dismiss) private var dismiss
    @State private var reason: Reason?
    @State private var note = ""
    @State private var sending = false
    @State private var problem: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Group {
                if sent {
                    ContentUnavailableView(
                        "Report sent",
                        systemImage: "checkmark.circle",
                        description: Text("Aaru will look at it.")
                    )
                } else {
                    form
                }
            }
            .background(Color(.paper))
            .navigationTitle("Report this \(noun)")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(sending)
    }

    private var form: some View {
        Form {
            Section {
                Picker("Why", selection: $reason) {
                    ForEach(Reason.allCases, id: \.self) { reason in
                        Text(reason.label).tag(Optional(reason))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Why")
            } footer: {
                Text("\(authorName) won't know you reported it.")
            }
            Section {
                TextField("What should Aaru know?", text: $note, axis: .vertical)
                    .lineLimit(3 ... 6)
                    .onChange(of: note) {
                        if note.count > Self.noteLimit {
                            note = String(note.prefix(Self.noteLimit))
                        }
                    }
            } header: {
                Text("Note (optional)")
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(Color(.danger))
                }
            }
        }
        .paperPage()
        .disabled(sending)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if sent {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(sending)
            }
            ToolbarItem(placement: .confirmationAction) {
                if sending {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Send", action: send)
                        .disabled(reason == nil)
                }
            }
        }
    }

    private func send() {
        guard let reason, !sending else { return }
        // Set before the task starts, so a second tap can't file the report twice.
        sending = true
        problem = nil
        Task {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            problem = await report(reason, trimmed.isEmpty ? nil : trimmed)
            sending = false
            sent = problem == nil
        }
    }
}

private extension ReportPostSheet.Reason {
    /// The same words as the web's report dialog.
    var label: String {
        switch self {
        case .spam: String(localized: "Spam")
        case .harassment: String(localized: "Harassment")
        case .impersonation: String(localized: "Pretending to be someone")
        case .other: String(localized: "Something else")
        }
    }
}
