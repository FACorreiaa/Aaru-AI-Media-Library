import SwiftUI

/// Settings → Delete account (§18, UX-021): its own last page on iPhone and iPad; the bottom
/// of the Account pane on the Mac.
struct DeleteAccountPage: View {
    var onDeleteAccount: () async -> String?

    var body: some View {
        Form {
            DeleteAccountSection(onDeleteAccount: onDeleteAccount)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(.paper))
        .navigationTitle("Delete account")
    }
}

/// What goes, the way to keep a copy first, and the button, confirmed.
struct DeleteAccountSection: View {
    var onDeleteAccount: () async -> String?

    @Environment(AppRouter.self) private var router
    @State private var confirms = false
    @State private var deleting = false
    @State private var problem: String?

    var body: some View {
        Section {
            Text("Deletes your library, lists, imports, friends and sessions from Aaru for good.")
            Button("Export your data first", systemImage: "square.and.arrow.down") { router.openSettings(.data) }
            Button(role: .destructive) {
                confirms = true
            } label: {
                HStack {
                    Text("Delete account").foregroundStyle(Color(.danger))
                    if deleting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(deleting)
            .confirmationDialog("Delete account?", isPresented: $confirms, titleVisibility: .visible) {
                Button("Delete account and library", role: .destructive, action: delete)
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(Color(.danger))
            }
        } header: {
            Text("Delete account")
        }
    }

    private func delete() {
        deleting = true
        Task {
            problem = await onDeleteAccount()
            deleting = false
        }
    }
}
