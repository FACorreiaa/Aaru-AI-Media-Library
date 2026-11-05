import Foundation
import Observation
import SwiftUI

/// The app's destinations (DESIGN.md §18), in sidebar order. iPhone's tab bar shows the first
/// four and More, Aaru's own list (`MoreScreen`) of Groups, Books, Manga, Music and Sports, each
/// pushed on More's one stack (NAV-005). Lists, Friends, Insights and Settings have no tab there
/// and are reached from Library (Lists, Insights), Groups and Friends & privacy (Friends), and
/// the account button.
enum AppTab: String, CaseIterable, Identifiable {
    case home, discover, library, calendar, lists, friends, groups, books, manga, music, sports, insights, settings
    /// iPhone's fifth tab: the list of the `more` destinations. Never in a sidebar.
    case moreMenu

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
        case .friends: "Friends"
        case .groups: "Groups"
        case .books: "Books"
        case .manga: "Manga"
        case .music: "Music"
        case .sports: "Sports"
        case .insights: "Insights"
        case .settings: "Settings"
        case .moreMenu: "More"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .discover: "binoculars"
        case .library: "books.vertical"
        case .calendar: "calendar"
        case .lists: "list.bullet.rectangle"
        case .friends: "person.2"
        case .groups: "bubble.left.and.bubble.right"
        case .books: "book"
        case .manga: "book.pages"
        case .music: "music.note"
        case .sports: "sportscourt"
        case .insights: "chart.bar"
        case .settings: "gearshape"
        case .moreMenu: "ellipsis"
        }
    }

    /// The kind a kind page shows (NAV-002): Books, Manga and Music. Nil for every other tab.
    var kind: MediaKind? {
        switch self {
        case .books: .book
        case .manga: .manga
        case .music: .music
        default: nil
        }
    }

    /// The destinations at the top of the sidebar. Friends sits between Lists and the More
    /// group (SOC-003, as on the web).
    static let primary: [AppTab] = [.home, .discover, .library, .calendar, .lists, .friends]

    /// The sidebar's More group, and iPhone's More tab (NAV-002). Sports (SPT-004) comes last,
    /// and only while the server has it on.
    static let more: [AppTab] = [.groups, .books, .manga, .music, .sports]

    /// Set apart at the bottom of the sidebar. The Mac has no Settings row: Settings is its
    /// Settings scene (⌘,).
    static var secondary: [AppTab] {
        #if os(macOS)
            [.insights]
        #else
            [.insights, .settings]
        #endif
    }

    /// The Mac's Go menu, in sidebar order; ⌘1…⌘9 go to the first nine.
    static let goMenu: [AppTab] = primary + more + [.insights]

    /// iPhone's tabs, in order. The `more` destinations are pushed from the last (NAV-005).
    static let compact: [AppTab] = [.home, .discover, .library, .calendar, .moreMenu]

    /// Has a place on iPhone, in the bar or under More. The rest are sidebar-only (§18, UX-001).
    var isInCompactTabBar: Bool {
        Self.compact.contains(self) || Self.more.contains(self)
    }
}

/// One place that says where the app is: the selected destination, what Settings shows, and the
/// requests the menu bar and keyboard send (⌘N, ⌘F, ⌘R, ⌘,). Shared by the main window and the
/// Mac Settings scene.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home {
        didSet { showInMore() }
    }

    /// iPhone: More's one stack (NAV-005). A `more` destination sits at the bottom, with whatever
    /// that destination pushed above it. Emptied by a pop or the tab bar, it goes back to the list.
    var morePath = NavigationPath() {
        didSet {
            guard morePath.isEmpty, moreRoot != nil else { return }
            moreRoot = nil
            // Friends lives on this stack on iPhone, so it left with it.
            showsFriendsInGroups = false
            if AppTab.more.contains(tab) {
                tab = .moreMenu
            }
        }
    }

    /// The bottom of `morePath`: a `NavigationPath` cannot be read back.
    private(set) var moreRoot: AppTab?

    /// Library's kind and status filter, here so Home's count chips can set it.
    var libraryFilter = LibraryFilter()
    /// Search over the catalog, as a sheet over whichever destination is showing (⌘F).
    var showsSearch = false
    /// iPhone: Library pushes Lists, since Lists has no tab there.
    var showsListsInLibrary = false
    /// iPhone: Groups pushes Friends, since Friends has no tab there.
    var showsFriendsInGroups = false
    /// A new list was asked for (⌘N, Home's "New list"); Lists starts one and clears it.
    var pendingNewList = false
    /// "Write about this" on a title page (BOARD-003): Friends opens on the Board and the composer
    /// takes this title once, then clears it.
    var pendingBoardTitle: BoardTitlePick?

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
    /// Bumped when a share link opens (SHR-002): the sheets the app shows from the top close, so
    /// the share sheet can take their place. One sheet can't be shown over another from here.
    private(set) var closeSheetsRequest = 0

    /// Bumped by ⌘R; the selected destination reloads (`refreshesOnCommand`).
    private(set) var refreshTick = 0

    /// Whether the main window is in a compact width right now (set by the root view).
    var isCompact = false {
        didSet {
            if isCompact {
                showInMore()
            } else {
                closeMore()
                if tab == .moreMenu {
                    tab = .home
                }
            }
        }
    }

    /// Whether this server has Sports on (`getSportSettings`); the Sports tab shows only then.
    var sportsAvailable = false {
        didSet {
            if !sportsAvailable, tab == .sports {
                tab = .home
            }
            if !sportsAvailable, moreRoot == .sports {
                closeMore()
            }
        }
    }

    /// Music's view (NAV-002): its albums, Concerts or Listens. Here so Library's menu and Insights
    /// can open Listens.
    var musicPane: MusicPane = .albums

    /// The Go menu's rows, without Sports while the server has it off.
    var goMenu: [AppTab] {
        AppTab.goMenu.filter { $0 != .sports || sportsAvailable }
    }

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

    /// Friends (SOC-003): its own destination in a sidebar. On iPhone it has no tab, so Groups
    /// pushes it; from the Settings sheet, the sheet closes first.
    func showFriends() {
        #if os(iOS)
            if isCompact {
                showsSettingsSheet = false
                tab = .groups
                showsFriendsInGroups = true
                return
            }
        #endif
        tab = .friends
    }

    /// Sports' Favorites, which Edit profile links to (SOC-001b): follows stay in Sports. From the
    /// Settings sheet, the sheet closes first.
    func showSportsFollows() {
        showsSettingsSheet = false
        select(.sports)
    }

    /// iPhone: a `more` destination shows on More's stack, from wherever it was asked for. One
    /// already there keeps what it pushed.
    private func showInMore() {
        guard isCompact, AppTab.more.contains(tab), moreRoot != tab else { return }
        moreRoot = tab
        morePath = NavigationPath([tab])
    }

    private func closeMore() {
        moreRoot = nil
        morePath = NavigationPath()
    }

    /// The tab bar's selection on iPhone. A `more` destination lights up More.
    var tabBarSelection: AppTab {
        AppTab.more.contains(tab) ? .moreMenu : tab
    }

    /// A tap in the tab bar on iPhone. More shows what it showed last.
    func selectInTabBar(_ selection: AppTab) {
        tab = selection == .moreMenu ? moreRoot ?? .moreMenu : selection
    }

    func select(_ destination: AppTab) {
        switch destination {
        case .lists: showLists()
        case .friends: showFriends()
        case .settings: openSettings()
        case .insights where isCompact:
            // No Insights tab on iPhone: Library's More menu holds it.
            tab = .library
        default: tab = destination
        }
    }

    /// Listens (MUS-008): a view of the Music page, from Library's menu and Insights.
    func showListens() {
        musicPane = .listens
        tab = .music
    }

    func showLibrary(status: LibraryStatus?) {
        showLibrary(LibraryFilter(status: status))
    }

    /// Library, filtered: to one status (Home's count chips) or one kind (the profile's tiles).
    func showLibrary(_ filter: LibraryFilter) {
        libraryFilter = filter
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

    /// Closes Search, the Settings sheet and the linked sheets MainTabs shows (`closeSheetsRequest`).
    func closeSheets() {
        showsSearch = false
        showsSettingsSheet = false
        closeSheetsRequest += 1
    }

    /// Signed out: back to Home with nothing of the last user's place.
    func reset() {
        tab = .home
        libraryFilter = LibraryFilter()
        showsSearch = false
        showsListsInLibrary = false
        showsFriendsInGroups = false
        musicPane = .albums
        sportsAvailable = false
        pendingNewList = false
        pendingBoardTitle = nil
        settingsPath = []
        showsSettingsSheet = false
        settingsPane = .account
        closeMore()
    }
}
