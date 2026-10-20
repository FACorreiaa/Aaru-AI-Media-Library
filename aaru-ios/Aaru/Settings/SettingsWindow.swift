#if os(macOS)
    import AaruAPI
    import SwiftUI

    /// The Mac Settings window (Cmd-,): the Settings tab's content, once someone is signed in.
    struct SettingsWindow: View {
        let api: Client?
        let imports: ImportsModel
        let library: LibraryModel
        let lists: ListsModel
        @Environment(SessionStore.self) private var session

        var body: some View {
            Group {
                if session.isSignedIn {
                    SettingsView(
                        api: api, imports: imports, library: library, lists: lists,
                        onSignOut: { Task { await flow.signOut() } },
                        onDeleteAccount: { await flow.deleteAccount() }
                    )
                } else {
                    ContentUnavailableView(
                        "Not signed in",
                        systemImage: "person.crop.circle",
                        description: Text("Sign in to Aaru in the main window first.")
                    )
                }
            }
            .frame(minWidth: 520, minHeight: 560)
        }

        private var flow: AuthFlow {
            AuthFlow(api: api, session: session)
        }
    }
#endif
