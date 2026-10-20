import AaruAPI
import AuthenticationServices
import SwiftUI
import WidgetKit

/// Routes on the session: welcome when signed out, the app when signed in.
struct RootView: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    let imports: ImportsModel
    let groups: GroupsModel
    @Environment(SessionStore.self) private var session
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var showsEmailSignIn = false
    @State private var tab: AppTab = .home
    @State private var errorMessage: String?
    /// A title a widget asked to open (`aaru://title/{id}`).
    @State private var linkedTitle: LinkedTitle?

    private var flow: AuthFlow {
        AuthFlow(api: api, session: session)
    }

    var body: some View {
        Group {
            if session.isSignedIn {
                // A sidebar on Mac and iPad, a tab bar on iPhone.
                TabView(selection: $tab) {
                    Tab("Home", systemImage: "house", value: AppTab.home) {
                        HomeScreen(api: api, library: library, lists: lists) { tab = .calendar }
                    }
                    Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                        LibraryView(
                            api: api, library: library, lists: lists, imports: imports,
                            onSignOut: { Task { await flow.signOut() } },
                            onDeleteAccount: { await flow.deleteAccount() }
                        )
                    }
                    Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
                        CalendarScreen(api: api, library: library, lists: lists)
                    }
                    Tab("Groups", systemImage: "bubble.left.and.bubble.right", value: AppTab.groups) {
                        GroupsScreen(groups: groups)
                    }
                    .badge(groups.mentionTotal)
                }
                .tabViewStyle(.sidebarAdaptable)
                // The tab's mention badge needs the counts before the tab is opened.
                .task { await groups.load() }
                .sheet(item: $linkedTitle) { link in
                    NavigationStack {
                        LibraryEntryDestination(id: link.id, api: api, library: library, lists: lists)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { linkedTitle = nil }
                                }
                            }
                    }
                }
            } else {
                WelcomeView(
                    api: api,
                    onAppleAuthorization: { authorization, nonce in
                        Task { await run { try await flow.signInWithApple(authorization, rawNonce: nonce) } }
                    },
                    onAppleError: { error in
                        // Closing Apple's sheet is not an error worth showing.
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            errorMessage = error.localizedDescription
                        }
                    },
                    onContinueWithEmail: { showsEmailSignIn = true },
                    onContinueWithGoogle: AppEnvironment.googleClientID.map { clientID in
                        {
                            Task {
                                await run {
                                    let google = GoogleSignIn(clientID: clientID)
                                    if let token = try await google.token(using: webAuthenticationSession) {
                                        try await flow.signInWithGoogle(token)
                                    }
                                }
                            }
                        }
                    }
                )
                .sheet(isPresented: $showsEmailSignIn) {
                    EmailSignInSheet(flow: flow)
                }
            }
        }
        // A signed-out device keeps nothing of the last user's library.
        .onChange(of: session.isSignedIn) { _, signedIn in
            if !signedIn {
                library.reset()
                lists.reset()
                imports.reset()
                groups.reset()
                HomeCache().clear()
                WidgetSnapshotStore.clear()
                WidgetCenter.shared.reloadAllTimelines()
                tab = .home
                linkedTitle = nil
            }
        }
        .onOpenURL { url in
            guard session.isSignedIn, let id = WidgetLink.libraryItemId(in: url) else { return }
            linkedTitle = LinkedTitle(id: id)
        }
        .alert(
            "Could not sign in",
            isPresented: Binding(get: { errorMessage != nil }, set: {
                if !$0 {
                    errorMessage = nil
                }
            })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    enum AppTab: Hashable {
        case home, library, calendar, groups
    }

    struct LinkedTitle: Identifiable {
        let id: String
    }

    private func run(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    RootView(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil), imports: ImportsModel(api: nil),
        groups: GroupsModel(api: nil)
    )
    .environment(SessionStore(keychain: SessionKeychain(service: "preview")))
}
