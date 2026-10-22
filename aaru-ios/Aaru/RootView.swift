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
    let settings: SettingsServices
    let groups: GroupsModel
    let realtime: RealtimeClient
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var showsEmailSignIn = false
    @State private var errorMessage: String?

    private var flow: AuthFlow {
        AuthFlow(api: api, session: session)
    }

    var body: some View {
        Group {
            if session.isSignedIn {
                MainTabs(
                    api: api, library: library, lists: lists, imports: imports, groups: groups,
                    realtime: realtime, settings: settingsContext
                )
            } else {
                WelcomeView(
                    api: api,
                    signedOutByServer: session.wasSignedOutByServer,
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
                        { Task { await signInWithGoogle(clientID: clientID) } }
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
                settings.reset()
                groups.reset()
                realtime.reset()
                router.reset()
                HomeCache().clear()
                WidgetSnapshotStore.clear()
                WidgetCenter.shared.reloadAllTimelines()
                #if os(iOS)
                    Task { await NowWatching.endAll() }
                #endif
            }
        }
        .alert("Could not sign in", isPresented: $errorMessage.isPresent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var settingsContext: SettingsContext {
        SettingsContext(
            api: api, imports: imports, models: settings, library: library, lists: lists,
            onSignOut: { Task { await flow.signOut() } },
            onDeleteAccount: { await flow.deleteAccount() }
        )
    }

    private func signInWithGoogle(clientID: String) async {
        await run {
            let google = GoogleSignIn(clientID: clientID)
            if let token = try await google.token(using: webAuthenticationSession) {
                try await flow.signInWithGoogle(token)
            }
        }
    }

    private func run(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The signed-in app: a sidebar on Mac and iPad, a five-tab bar on iPhone (DESIGN.md §18).
private struct MainTabs: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    let imports: ImportsModel
    let groups: GroupsModel
    let realtime: RealtimeClient
    let settings: SettingsContext

    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #else
        @Environment(\.openSettings) private var openSettings
    #endif
    /// A title a widget or an alert asked to open (`aaru://title/{id}`).
    @State private var linkedTitle: LinkedTitle?
    /// An agent request a notification asked to open (OUT-004).
    @State private var linkedPlan: LinkedTitle?

    /// iPhone and a compact iPad window: a tab bar of five, no sidebar. `.sidebarOnly` alone
    /// still counts a hidden tab there and turns the fifth into More, so those tabs are left out.
    private var compactTabBar: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    private func isShown(_ destination: AppTab) -> Bool {
        !compactTabBar || destination.isInCompactTabBar
    }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            ForEach(AppTab.primary.filter(isShown)) { destination in
                Tab(destination.title, systemImage: destination.symbol, value: destination) {
                    screen(for: destination)
                }
                .badge(destination == .groups ? groups.mentionTotal : 0)
                // Lists has no tab on iPhone; it opens from Library and Home (§18).
                .tabPlacement(destination.isInCompactTabBar ? .automatic : .sidebarOnly)
            }
            if !compactTabBar {
                TabSection {
                    ForEach(AppTab.secondary) { destination in
                        Tab(destination.title, systemImage: destination.symbol, value: destination) {
                            screen(for: destination)
                        }
                        .tabPlacement(.sidebarOnly)
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(macOS)
            .frame(minWidth: 760, minHeight: 520)
        #endif
            .sheet(item: $linkedPlan) { link in
                if let api {
                    PlanSheet(api: api, id: link.id) { linkedPlan = nil }
                }
            }
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
            .sheet(isPresented: $router.showsSearch) {
                SearchView(api: api, library: library, lists: lists)
            }
        #if os(iOS)
            .sheet(isPresented: $router.showsSettingsSheet) {
                settingsScreen(showsDone: true)
            }
            .onChange(of: sizeClass, initial: true) { _, size in
                router.isCompact = size == .compact
                // A sidebar-only destination has no tab once the window turns compact.
                if size == .compact, !router.tab.isInCompactTabBar {
                    router.select(router.tab)
                }
            }
        #else
            .onChange(of: router.settingsWindowRequest) { openSettings() }
        #endif
            // Screens outside the tab (a title's "Discuss in a group…") reach groups through this.
            .environment(groups)
            .onChange(of: groups.openRequest) { _, request in
                if request != nil {
                    router.tab = .groups
                }
            }
            // The tab's mention badge needs the counts before the tab is opened.
            .task { await groups.load() }
            // The socket is open while the app is active, and its events keep groups current.
            .task { await groups.follow() }
            .task(id: scenePhase) {
                if scenePhase == .background {
                    realtime.stop()
                } else {
                    realtime.start()
                }
            }
        #if os(iOS)
            // Live Activity tokens go up while signed in; signing out cancels it.
            .task { await LiveActivityRegistrar.current?.follow() }
        #endif
            // A notification tapped before sign-in, or before the app was running, waits in
            // PushInbox; this view only exists signed in, so it reads it on appear too (UX-012).
            .onChange(of: PushInbox.shared.planID, initial: true) { _, id in
                guard let id else { return }
                linkedPlan = LinkedTitle(id: id)
                PushInbox.shared.planID = nil
            }
            .onChange(of: PushInbox.shared.libraryItemID, initial: true) { _, id in
                guard let id else { return }
                linkedTitle = LinkedTitle(id: id)
                PushInbox.shared.libraryItemID = nil
            }
            .onChange(of: PushInbox.shared.groupLink, initial: true) { _, url in
                guard let url else { return }
                openGroup(url)
                PushInbox.shared.groupLink = nil
            }
            .onOpenURL(perform: open)
    }

    private func open(_ url: URL) {
        if let id = WidgetLink.libraryItemId(in: url) {
            linkedTitle = LinkedTitle(id: id)
        } else if !router.open(url) {
            openGroup(url)
        }
    }

    /// A group alert or link: the channel it names, or the Groups tab (GRP-012).
    private func openGroup(_ url: URL) {
        switch GroupLink(url) {
        case .groups?: router.tab = .groups
        // The Groups tab opens itself for a channel request.
        case let .channel(request)?: groups.openRequest = request
        case nil: break
        }
    }

    @ViewBuilder
    private func screen(for destination: AppTab) -> some View {
        switch destination {
        case .home:
            HomeScreen(
                api: api, library: library, lists: lists, imports: imports,
                onSelectTab: { router.select($0) },
                onShowLibrary: { router.showLibrary(status: $0) }
            )
        case .discover:
            DiscoverScreen(api: api, library: library, lists: lists)
        case .library:
            @Bindable var router = router
            LibraryView(api: api, library: library, lists: lists, filter: $router.libraryFilter)
        case .calendar:
            CalendarScreen(api: api, library: library, lists: lists)
        case .lists:
            ListsScreen(lists: lists, library: library, api: api)
        case .groups:
            GroupsScreen(groups: groups)
        case .insights:
            NavigationStack {
                InsightsView(api: api, library: library)
            }
        case .settings:
            settingsScreen(showsDone: false)
        }
    }

    private func settingsScreen(showsDone: Bool) -> some View {
        SettingsView(context: settings, showsDone: showsDone)
    }

    struct LinkedTitle: Identifiable {
        let id: String
    }
}

extension Optional {
    /// For `.alert(isPresented:)` over an optional message: true while there is one; setting
    /// false clears it.
    var isPresent: Bool {
        get { self != nil }
        set {
            if !newValue {
                self = nil
            }
        }
    }
}

#Preview {
    RootView(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil), imports: ImportsModel(api: nil),
        settings: SettingsServices(api: nil), groups: GroupsModel(api: nil, realtime: nil),
        realtime: RealtimeClient(baseURL: nil) { nil }
    )
    .environment(SessionStore(keychain: SessionKeychain(service: "preview")))
    .environment(AppRouter())
}
