import AaruAPI
import SwiftUI

/// Report a friend's post (BOARD-003): why, from four reasons, and an optional note. It goes to
/// Aaru through the user-report route with the post named; the friend is not told.
struct ReportPostSheet: View {
    typealias Reason = Components.Schemas.ReportCreate.ReasonPayload

    let model: PostModel

    /// What the note may hold: the server takes 1,000 characters and the post's id goes first.
    private static let noteLimit = 900

    @Environment(\.dismiss) private var dismiss
    @State private var reason: Reason?
    @State private var note = ""
    @State private var sending = false
    @State private var failed = false
    @State private var sent = false

    private var authorName: String {
        model.post?.author.inviteName ?? "They"
    }

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
            .navigationTitle("Report this post")
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
                if failed, let problem = model.problem {
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
        failed = false
        Task {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let reported = await model.report(reason: reason, note: trimmed.isEmpty ? nil : trimmed)
            sending = false
            if reported {
                sent = true
            } else {
                failed = true
            }
        }
    }
}

private extension ReportPostSheet.Reason {
    /// The same words as the web's report dialog.
    var label: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Harassment"
        case .impersonation: "Pretending to be someone"
        case .other: "Something else"
        }
    }
}
