import Foundation
import Observation

/// The app's destinations (DESIGN.md §18), in sidebar order. iPhone's tab bar shows the first
/// four and Groups; Lists, Insights and Settings live in the sidebar (iPad, Mac) and are reached
/// from Library, Home and the account button on iPhone.
enum AppTab: String, CaseIterable, Identifiable {
    case home, discover, library, calendar, lists, groups, insights, settings

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
        case .insights: "Insights"
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
        case .insights: "chart.bar"
        case .settings: "gearshape"
        }
    }

    /// The six destinations, above the gap in the sidebar.
    static let primary: [AppTab] = [.home, .discover, .library, .calendar, .lists, .groups]

    /// Set apart at the bottom of the sidebar. The Mac has no Settings row: Settings is its
    /// Settings scene (⌘,).
    static var secondary: [AppTab] {
        #if os(macOS)
            [.insights]
        #else
            [.insights, .settings]
        #endif
    }

    /// The Mac's Go menu: ⌘1…⌘7 for the seven sidebar rows.
    static let goMenu: [AppTab] = primary + [.insights]

    /// Kept in the compact tab bar. The rest are sidebar-only there (§18, UX-001).
    var isInCompactTabBar: Bool {
        [.home, .discover, .library, .calendar, .groups].contains(self)
    }
}

/// One place that says where the app is: the selected destination, what Settings shows, and the
/// requests the menu bar and keyboard send (⌘N, ⌘F, ⌘R, ⌘,). Shared by the main window and the
/// Mac Settings scene.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
    /// Library's kind and status filter, here so Home's count chips can set it.
    var libraryFilter = LibraryFilter()
    /// Search over the catalog, as a sheet over whichever destination is showing (⌘F).
    var showsSearch = false
    /// iPhone: Library pushes Lists, since Lists has no tab there.
    var showsListsInLibrary = false
    /// A new list was asked for (⌘N, Home's "New list"); Lists starts one and clears it.
    var pendingNewList = false

    /// iPhone and iPad: the Settings stack (a page, an import job, History).
    var settingsPath: [SettingsRoute] = []
    /// iPhone (and a compact iPad window): Settings as a sheet from the account button.
    var showsSettingsSheet = false
    /// Mac: the Settings scene's selected pane.
    var settingsPane: SettingsPage = .account
    /// Mac: Your data's pane pushes History when this is set (it clears it).
    var showsHistoryPane = false
    /// Mac: bumped to ask the main window to open the Settings scene.
    private(set) var settingsWindowRequest = 0

    /// Bumped by ⌘R; the selected destination reloads (`refreshesOnCommand`).
    private(set) var refreshTick = 0

    /// Whether the main window is in a compact width right now (set by the root view).
    var isCompact = false

    /// Opens Settings on a page, or on its list when `page` is nil, wherever Settings lives on
    /// this platform: the Settings scene (Mac), the sidebar row (regular width) or a sheet.
    func openSettings(_ page: SettingsPage? = nil) {
        #if os(macOS)
            settingsPane = page?.macPane ?? settingsPane
            settingsWindowRequest += 1
        #else
            settingsPath = page.map { [.page($0)] } ?? []
            if isCompact {
                showsSettingsSheet = true
            } else {
                tab = .settings
            }
        #endif
    }

    /// Settings → Your data → History: every journaled action, with Undo (UX-060).
    func openHistory() {
        #if os(macOS)
            settingsPane = .data
            showsHistoryPane = true
            settingsWindowRequest += 1
        #else
            openSettings(.data)
            settingsPath.append(.history)
        #endif
    }

    /// Lists: its own destination in a sidebar, pushed from Library on iPhone.
    func showLists(startingNew: Bool = false) {
        pendingNewList = startingNew
        if isCompact {
            tab = .library
            showsListsInLibrary = true
        } else {
            tab = .lists
        }
    }

    func select(_ destination: AppTab) {
        switch destination {
        case .lists: showLists()
        case .settings: openSettings()
        case .insights where isCompact:
            // No Insights tab on iPhone: Library's More menu holds it.
            tab = .library
        default: tab = destination
        }
    }

    func showLibrary(status: LibraryStatus?) {
        libraryFilter = LibraryFilter(status: status)
        tab = .library
    }

    func refresh() {
        refreshTick += 1
    }

    /// `aaru://settings` and `aaru://settings/<slug>` (UX-017). False for any other link.
    func open(_ url: URL) -> Bool {
        guard url.scheme == "aaru", url.host() == "settings" else { return false }
        let slug = url.pathComponents.first { $0 != "/" }
        // Trakt's sign-in returns to `aaru://settings/trakt`: that is Import.
        openSettings(slug == "trakt" ? .imports : slug.flatMap(SettingsPage.init(rawValue:)))
        return true
    }

    /// Signed out: back to Home with nothing of the last user's place.
    func reset() {
        tab = .home
        libraryFilter = LibraryFilter()
        showsSearch = false
        showsListsInLibrary = false
        pendingNewList = false
        settingsPath = []
        showsSettingsSheet = false
        settingsPane = .account
    }
}
