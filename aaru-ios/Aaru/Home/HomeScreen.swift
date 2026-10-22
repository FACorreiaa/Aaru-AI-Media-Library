import AaruAPI
import SwiftUI

/// Home, drawn as the Field (APP-009, APP-013, DESIGN.md §1 and §13): what a player is playing
/// now (SCR-008, §15) sits under the heading when there is something; Tonight leads, then
/// Continue watching, the albums being listened to (MUS-001), what airs next, Start watching and
/// Unfinished as Trakt-style rows of cards, then Discover's public rows (DISC-001). Requests
/// waiting for the user, the last import, the week, the library's counts, the recap and the user's
/// lists sit in a side column on wide screens and after the rows on a phone. Renders from the
/// cache first, then refreshes. The sections are in `HomeSections.swift`.
struct HomeScreen: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    /// The user's imports, for the newest one's note. Nil in previews.
    var imports: ImportsModel?
    /// Switches the app to another destination (Calendar, Discover).
    var onSelectTab: (AppTab) -> Void
    /// Switches to Library, filtered: to one status (the count chips) or one kind (the profile).
    var onShowLibrary: (LibraryFilter) -> Void

    @State var model: HomeModel
    @State var recap: RecapPeriod?
    @State var listTarget: CatalogHit?
    /// Home's stack: a title opened from a card or from an airing's sheet.
    @State var path: [String] = []
    /// Home's own width: a narrow regular window (iPad at 2/3, a small Mac window) takes the
    /// phone's single column, since the 340pt side column would squeeze the rows.
    @State private var width: CGFloat = 0
    @Environment(AppRouter.self) var router
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        var compact: Bool {
            sizeClass == .compact || (width > 0 && width < Self.sideColumnMinWidth)
        }
    #else
        var compact: Bool {
            width > 0 && width < Self.sideColumnMinWidth
        }
    #endif

    private static let sideColumnMinWidth: CGFloat = 760

    init(
        api: Client?,
        library: LibraryModel,
        lists: ListsModel,
        imports: ImportsModel? = nil,
        model: HomeModel? = nil,
        onSelectTab: @escaping (AppTab) -> Void = { _ in },
        onShowLibrary: @escaping (LibraryFilter) -> Void = { _ in }
    ) {
        self.api = api
        self.library = library
        self.lists = lists
        self.imports = imports
        self.onSelectTab = onSelectTab
        self.onShowLibrary = onShowLibrary
        _model = State(initialValue: model ?? HomeModel(api: api, library: library))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Home")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                // The profile (GAM-006b) leads; the top trailing spot is the account button's (§18).
                .profileEntry(api: api, library: library, lists: lists) { onShowLibrary(LibraryFilter(kind: $0)) }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Search", systemImage: "magnifyingglass") { router.showsSearch = true }
                    }
                    #if os(macOS)
                        ToolbarItem {
                            Button("Refresh", systemImage: "arrow.clockwise") { Task { await reload() } }
                                .disabled(model.isLoading)
                        }
                    #endif
                }
                .accountButton()
                // Each appearance: the first load, or a refetch if the library changed while away.
                .task {
                    await model.loadIfNeeded()
                    await model.shelfChanged()
                }
                .task { await model.loadPlans() }
                // Players report only on a change, so what is playing is asked again every 30 s
                // while Home is open and the app is in front; the card's clock runs in between.
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await model.loadNowPlaying()
                        try? await Task.sleep(for: .seconds(30))
                    }
                }
                .task { await imports?.load() }
                .task {
                    if !lists.hasLoaded {
                        await lists.load()
                    }
                }
                // View → Refresh (⌘R) while Home is showing.
                .refreshesOnCommand(.home) { await reload() }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
                // Adds from Search and Discover land in the library; Home's rows come from other endpoints.
                .onChange(of: library.revision) { Task { await model.shelfChanged() } }
                // A request answered anywhere (a notification's sheet too) leaves "Waiting for you" (UX-082).
                .onReceive(NotificationCenter.default.publisher(for: .aaruPlanDecided)) { note in
                    guard let plan = note.object as? AgentPlan else { return }
                    Task { await model.planDecided(plan) }
                }
                .sheet(item: $listTarget) { hit in
                    ListPickerSheet(
                        ref: .init(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year),
                        titleName: hit.title,
                        lists: lists
                    )
                }
                // "Airing soon" opens the episode, as the calendar does, with "Open show" in it (UX-092).
                .sheet(
                    isPresented: Binding(
                        get: { model.airingFeed.openedID != nil },
                        set: {
                            if !$0 {
                                model.airingFeed.openedID = nil
                            }
                        }
                    ),
                    onDismiss: { Task { await model.shelfChanged() } },
                    content: { CalendarEpisodeSheet(feed: model.airingFeed) { path.append($0) } }
                )
                .recapStory($recap, api: api)
                .safeAreaInset(edge: .bottom) {
                    ProblemBanner(message: model.problem) { model.problem = nil }
                }
                .undoToast()
                .background { FieldBackground() }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @ViewBuilder
    private var content: some View {
        if model.loadFailed, model.isEmpty, model.discover.isEmpty, model.nowPlaying.isEmpty {
            LoadFailedView(
                title: "Couldn't load Home",
                message: "Aaru could not reach the server. Check your connection and try again."
            ) { await reload() }
        } else if model.isEmpty, model.discover.isEmpty, model.nowPlaying.isEmpty, model.hasLoaded {
            ContentUnavailableView {
                Label(HomeEmptyCopy.headline, systemImage: "sparkles.tv")
            } description: {
                Text("What you are watching, reading and listening to, and what airs next, lands here.")
            } actions: {
                Button("Browse Discover") { onSelectTab(.discover) }
                    .buttonStyle(.borderedProminent)
                Button("Search") { router.showsSearch = true }
                    .buttonStyle(.bordered)
                Button(HomeEmptyCopy.importAction) { router.openSettings(.imports) }
                    .buttonStyle(.bordered)
            }
        } else {
            ScrollView {
                if model.isEmpty, model.discover.isEmpty, model.nowPlaying.isEmpty {
                    // The first load, inside the scroll view so pull to refresh works already.
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .containerRelativeFrame(.vertical)
                } else {
                    sections.padding(.vertical, 16)
                }
            }
            .refreshable { await reload() }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            nowPlayingSection
            if compact {
                tonightSection
                waitingSection
                welcome
                ownRows
                sideBlocks
                discoverRows
            } else {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 28) {
                        tonightSection
                        welcome
                        ownRows
                        discoverRows
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 24) {
                        waitingSection
                        sideBlocks
                    }
                    .frame(width: 340)
                }
            }
        }
    }

    /// Full width under the heading, above the split, so it leads on every screen size.
    @ViewBuilder private var nowPlayingSection: some View {
        if !model.nowPlaying.isEmpty {
            NowPlayingCard(items: model.nowPlaying, wide: !compact)
                .padding(.horizontal, 20)
        }
    }

    func cardWidth(_ size: HomeCardSize) -> CGFloat {
        size.width(compact: compact, dynamicType: dynamicType)
    }

    func reload() async {
        await model.load()
        await model.loadNowPlaying()
        await model.loadPlans()
        await imports?.load()
    }
}
