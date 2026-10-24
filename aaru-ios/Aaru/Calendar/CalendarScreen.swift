import AaruAPI
import SwiftUI

/// What airs from the user's own shows: the CAT week grid (DESIGN.md §14), Stremio's month with
/// its agenda (§7), or Missed, one switch apart. All read the same `CalendarFeed`; filters apply
/// to every mode, Week and Month group by day or channel (CAL-005), and any episode opens the
/// episode sheet (CAL-003).
struct CalendarScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case week, month, missed

        var id: Self {
            self
        }

        var label: String {
            switch self {
            case .week: "Week"
            case .month: "Month"
            case .missed: "Missed"
            }
        }
    }

    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @AppStorage("calendar.mode") private var mode: Mode = .week
    @AppStorage("calendar.hideWatched") private var hideWatched = false
    @AppStorage("calendar.only") private var only: CalendarFilter.Only = .all
    @AppStorage("calendar.kind") private var kind: CalendarFilter.Kind = .all
    @AppStorage("calendar.grouping") private var grouping: CalendarFilter.Grouping = .day
    @State private var path: [String] = []
    @State private var feed: CalendarFeed
    @State private var week: WeekModel
    @State private var month: MonthModel
    @Environment(AppRouter.self) private var router
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// A phone's bar has no room for the switch beside Week's arrows and the filter menu, so it
    /// sits under the bar there; wider windows keep it in the bar's centre.
    private var switchUnderBar: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    init(api: Client?, library: LibraryModel, lists: ListsModel, feed: CalendarFeed? = nil, today: Date = .now) {
        self.api = api
        self.library = library
        self.lists = lists
        let feed = feed ?? CalendarFeed(api: api, library: library)
        _feed = State(initialValue: feed)
        _week = State(initialValue: WeekModel(feed: feed, today: today))
        _month = State(initialValue: MonthModel(feed: feed, today: today))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case .week:
                    WeekView(model: week, onSearch: search, onClearFilters: clearFilters)
                case .month:
                    MonthView(model: month, onSearch: search, onClearFilters: clearFilters) { path.append($0) }
                case .missed:
                    CatchUpView(feed: feed, window: missedWindow, onClearFilters: clearFilters) {
                        await feed.fetch(missedWindow)
                    }
                }
            }
            .navigationTitle("Calendar")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    if !switchUnderBar {
                        ToolbarItem(placement: .principal) { modePicker.fixedSize() }
                    }
                    ToolbarItem(placement: .secondaryAction) { filterMenu }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        if switchUnderBar {
                            modePicker
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        if feed.pendingShows > 0 {
                            pendingCaption
                        }
                    }
                }
                // A Month day sheet presents its own episode sheet (UX-068).
                .sheet(isPresented: Binding(
                    get: { feed.openedID != nil && !feed.isDaySheetOpen }, set: {
                        if !$0 {
                            feed.openedID = nil
                        }
                    }
                )) {
                    CalendarEpisodeSheet(feed: feed) { path.append($0) }
                }
                .onChange(of: currentFilter, initial: true) { feed.filter = currentFilter }
                .task(id: mode) { await loadIfNeeded() }
                .task(id: feed.pendingShows > 0) { await feed.recheckWhilePending() }
                .refreshable { await reload() }
                .refreshesOnCommand(.calendar) { await reload() }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
                .safeAreaInset(edge: .bottom) {
                    ProblemBanner(message: feed.problem) { feed.problem = nil }
                }
                .background(Color(.paper))
        }
    }

    /// CAL-004: an import's shows are still loading their episodes; the feed asks again.
    private var pendingCaption: some View {
        Label(
            "Loading episodes for \(feed.pendingShows) \(feed.pendingShows == 1 ? "show" : "shows")…",
            systemImage: "arrow.triangle.2.circlepath"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var modePicker: some View {
        Picker("View", selection: $mode) {
            ForEach(Mode.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var currentFilter: CalendarFilter {
        CalendarFilter(hideWatched: hideWatched, only: only, kind: kind, grouping: grouping)
    }

    private var filterMenu: some View {
        Menu {
            // A layout, not a filter: Missed is already by show, and Clear filters keeps it.
            if mode != .missed {
                Picker("Group by", selection: $grouping) {
                    ForEach(CalendarFilter.Grouping.allCases) { Text($0.label).tag($0) }
                }
                Divider()
            }
            Toggle("Hide watched", isOn: $hideWatched)
            Picker("Episodes", selection: $only) {
                ForEach(CalendarFilter.Only.allCases) { Text($0.label).tag($0) }
            }
            Picker("Kind", selection: $kind) {
                ForEach(CalendarFilter.Kind.allCases) { Text($0.label).tag($0) }
            }
            if currentFilter.isActive {
                Button("Clear filters", role: .destructive) {
                    hideWatched = false
                    only = .all
                    kind = .all
                }
            }
        } label: {
            Label(
                "Filters",
                systemImage: currentFilter.isActive
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
    }

    private func search() {
        router.showsSearch = true
    }

    /// Empty states offer it only while a filter hides something (UX-067).
    private var clearFilters: (() -> Void)? {
        guard currentFilter.isActive else { return nil }
        return {
            hideWatched = false
            only = .all
            kind = .all
        }
    }

    /// The last four weeks to the end of today: whole days, so a load stays "covered" as the
    /// clock moves on. Missed keeps only what has aired.
    private var missedWindow: Range<Date> {
        let today = feed.calendar.startOfDay(for: .now)
        let start = feed.calendar.date(byAdding: .day, value: -CatchUpView.days, to: today) ?? today
        let end = feed.calendar.date(byAdding: .day, value: 1, to: today) ?? .now
        return start ..< end
    }

    private func loadIfNeeded() async {
        switch mode {
        case .week: await week.loadIfNeeded()
        case .month: await month.loadIfNeeded()
        case .missed: await feed.ensure(missedWindow, fetching: missedWindow)
        }
    }

    private func reload() async {
        switch mode {
        case .week: await week.load()
        case .month: await month.load()
        case .missed: await feed.fetch(missedWindow)
        }
    }
}

// MARK: Previews

#Preview("Mac · month", traits: .fixedLayout(width: 1280, height: 800)) {
    CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
        .defaultAppStorage(.preview(mode: .month))
        .environment(AppRouter())
}

#Preview("Mac · month · dark", traits: .fixedLayout(width: 1280, height: 800)) {
    CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
        .defaultAppStorage(.preview(mode: .month))
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}

#Preview("Mac · month · by channel", traits: .fixedLayout(width: 1280, height: 800)) {
    CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
        .defaultAppStorage(.preview(mode: .month, grouping: .channel))
        .environment(AppRouter())
}

#Preview("Mac · week · by channel", traits: .fixedLayout(width: 1280, height: 720)) {
    CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
        .defaultAppStorage(.preview(mode: .week, grouping: .channel))
        .environment(AppRouter())
}

#Preview("Mac · week", traits: .fixedLayout(width: 1280, height: 720)) {
    CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
        .defaultAppStorage(.preview(mode: .week))
        .environment(AppRouter())
}

#if os(iOS)
    #Preview("iPhone · month") {
        CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
            .defaultAppStorage(.preview(mode: .month))
            .environment(AppRouter())
            .environment(\.horizontalSizeClass, .compact)
    }

    #Preview("iPhone · week · dark") {
        CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
            .defaultAppStorage(.preview(mode: .week))
            .environment(AppRouter())
            .environment(\.horizontalSizeClass, .compact)
            .preferredColorScheme(.dark)
    }

    #Preview("iPhone · week · by channel") {
        CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
            .defaultAppStorage(.preview(mode: .week, grouping: .channel))
            .environment(AppRouter())
            .environment(\.horizontalSizeClass, .compact)
    }
#endif

#Preview("Empty") {
    CalendarScreen(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: CalendarFeed(preview: [])
    )
    .environment(AppRouter())
}

private extension UserDefaults {
    static func preview(mode: CalendarScreen.Mode, grouping: CalendarFilter.Grouping = .day) -> UserDefaults {
        let suite = "calendar-preview-\(mode.rawValue)-\(grouping.rawValue)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.set(mode.rawValue, forKey: "calendar.mode")
        defaults.set(grouping.rawValue, forKey: "calendar.grouping")
        return defaults
    }
}
