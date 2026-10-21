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
    /// Library's kind and status filter, here so Home's count chips can set it.
    @State private var libraryFilter = LibraryFilter()
    @State private var errorMessage: String?
    /// A title a widget asked to open (`aaru://title/{id}`).
    @State private var linkedTitle: LinkedTitle?
    /// An agent request a notification asked to open (OUT-004).
    @State private var linkedPlan: LinkedTitle?

    private var flow: AuthFlow {
        AuthFlow(api: api, session: session)
    }

    var body: some View {
        Group {
            if session.isSignedIn {
                // A sidebar on Mac and iPad, a tab bar on iPhone.
                TabView(selection: $tab) {
                    ForEach(AppTab.allCases) { destination in
                        Tab(destination.title, systemImage: destination.symbol, value: destination) {
                            screen(for: destination)
                        }
                        .badge(destination == .groups ? groups.mentionTotal : 0)
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                .sheet(item: $linkedPlan) { link in
                    if let api {
                        PlanSheet(api: api, id: link.id) { linkedPlan = nil }
                    }
                }
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
                libraryFilter = LibraryFilter()
                linkedTitle = nil
                linkedPlan = nil
            }
        }
        .onChange(of: PushInbox.shared.planID, initial: true) { _, id in
            guard session.isSignedIn, let id else { return }
            linkedPlan = LinkedTitle(id: id)
            PushInbox.shared.planID = nil
        }
        // A tapped notification, possibly from before the app was running.
        .onChange(of: PushInbox.shared.libraryItemID, initial: true) { _, id in
            guard session.isSignedIn, let id else { return }
            linkedTitle = LinkedTitle(id: id)
            PushInbox.shared.libraryItemID = nil
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

    /// The app's destinations, in tab-bar and sidebar order.
    enum AppTab: String, CaseIterable, Identifiable {
        case home, discover, library, calendar, lists, groups, settings

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .home: "Home"
            case .discover: "Discover"
            case .library: "Library"
            case .calendar: "Calendar"
            case .lists: "Lists"
            case .groups: "Groups"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .home: "house"
            case .discover: "binoculars"
            case .library: "books.vertical"
            case .calendar: "calendar"
            case .lists: "list.bullet.rectangle"
            case .groups: "bubble.left.and.bubble.right"
            case .settings: "gearshape"
            }
        }
    }

    @ViewBuilder
    private func screen(for destination: AppTab) -> some View {
        switch destination {
        case .home:
            HomeScreen(
                api: api, library: library, lists: lists,
                onSelectTab: { tab = $0 },
                onShowLibrary: { status in
                    libraryFilter = LibraryFilter(status: status)
                    tab = .library
                }
            )
        case .discover:
            DiscoverScreen(api: api, library: library, lists: lists)
        case .library:
            LibraryView(api: api, library: library, lists: lists, filter: $libraryFilter)
        case .calendar:
            CalendarScreen(api: api, library: library, lists: lists)
        case .lists:
            NavigationStack {
                ListsView(lists: lists, library: library, api: api)
            }
        case .groups:
            GroupsScreen(groups: groups)
        case .settings:
            SettingsView(
                api: api, imports: imports, library: library, lists: lists,
                onSignOut: { Task { await flow.signOut() } },
                onDeleteAccount: { await flow.deleteAccount() }
            )
        }
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
