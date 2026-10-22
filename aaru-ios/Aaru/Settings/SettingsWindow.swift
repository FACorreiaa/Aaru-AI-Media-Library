#if os(macOS)
    import SwiftUI

    /// The Mac Settings scene (⌘, and the app menu), the only Settings on the Mac (§18): seven
    /// panes in Settings' order, each the same page view iPhone and iPad push. Delete account
    /// sits at the bottom of Account.
    struct SettingsWindow: View {
        let context: SettingsContext
        @Environment(SessionStore.self) private var session
        @Environment(AppRouter.self) private var router

        var body: some View {
            @Bindable var router = router
            Group {
                if session.isSignedIn {
                    TabView(selection: $router.settingsPane) {
                        ForEach(SettingsPage.macPanes) { page in
                            Tab(page.title, systemImage: page.paneSymbol, value: page) {
                                SettingsPane(page: page, context: context)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Not signed in",
                        systemImage: "person.crop.circle",
                        description: Text("Sign in to Aaru in the main window first.")
                    )
                }
            }
            .frame(minWidth: 560, idealWidth: 640, maxWidth: 820, minHeight: 480, idealHeight: 640)
        }
    }

    /// One pane: its page in a stack of its own, for an import job or History.
    private struct SettingsPane: View {
        let page: SettingsPage
        let context: SettingsContext
        @Environment(AppRouter.self) private var router
        @State private var path: [SettingsRoute] = []

        var body: some View {
            NavigationStack(path: $path) {
                SettingsPageView(page: page, context: context, push: { path.append($0) }, includesDeleteInAccount: true)
                    .navigationDestination(for: SettingsRoute.self) { route in
                        SettingsRouteView(route: route, context: context) { path.append($0) }
                    }
            }
            .onChange(of: router.showsHistoryPane, initial: true) { _, shows in
                guard shows, page == .data else { return }
                router.showsHistoryPane = false
                path = [.history]
            }
        }
    }

    extension SettingsPage {
        /// Outline symbols, as Mac Settings panes use.
        var paneSymbol: String {
            switch self {
            case .account: "person.crop.circle"
            case .friends: "person.2"
            case .notifications: "bell.badge"
            case .imports: "tray.and.arrow.down"
            case .connections: "app.connected.to.app.below"
            case .data: "externaldrive"
            case .about: "info.circle"
            case .delete: "trash"
            }
        }
    }
#endif
