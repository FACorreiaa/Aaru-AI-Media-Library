#if os(macOS)
    import AaruAPI
    import SwiftUI

    /// The Mac Settings window (Cmd-,): the Settings tab's groups as panes, once someone is signed
    /// in. Insights stays in the main window.
    struct SettingsWindow: View {
        let api: Client?
        let imports: ImportsModel
        let library: LibraryModel
        let lists: ListsModel
        @Environment(SessionStore.self) private var session
        @State private var account: Components.Schemas.Me?
        @State private var importsPath: [SettingsRoute] = []

        var body: some View {
            Group {
                if session.isSignedIn {
                    panes
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

        private var panes: some View {
            TabView {
                Tab("Account", systemImage: "person.crop.circle") {
                    NavigationStack {
                        AccountSettings(
                            api: api, imports: imports, account: $account,
                            onSignOut: { Task { await flow.signOut() } }
                        )
                    }
                }
                Tab("Imports & export", systemImage: "tray.and.arrow.down") {
                    NavigationStack(path: $importsPath) {
                        ImportsSettings(api: api, imports: imports) { importsPath.append(.job($0)) }
                            .navigationDestination(for: SettingsRoute.self) { route in
                                if case let .job(id) = route {
                                    ImportDetailView(id: id, imports: imports, library: library, lists: lists, api: api)
                                }
                            }
                    }
                }
                Tab("Connected apps", systemImage: "app.connected.to.app.below") {
                    NavigationStack { ConnectedAppsSettings(api: api, imports: imports) }
                }
                Tab("About", systemImage: "info.circle") {
                    NavigationStack { AboutView(onDeleteAccount: { await flow.deleteAccount() }) }
                }
            }
        }

        private var flow: AuthFlow {
            AuthFlow(api: api, session: session)
        }
    }
#endif
