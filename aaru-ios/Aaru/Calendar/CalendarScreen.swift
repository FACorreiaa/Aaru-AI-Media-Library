import AaruAPI
import SwiftUI

/// What airs from the user's own shows: the CAT week grid (DESIGN.md §14) or Stremio's month with
/// its agenda (§7), one switch apart. Both read the same `CalendarFeed`.
struct CalendarScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case week, month

        var id: Self {
            self
        }

        var label: String {
            switch self {
            case .week: "Week"
            case .month: "Month"
            }
        }
    }

    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @AppStorage("calendar.mode") private var mode: Mode = .week
    @State private var feed: CalendarFeed
    @State private var week: WeekModel
    @State private var month: MonthModel
    @State private var showsSearch = false

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
        NavigationStack {
            Group {
                switch mode {
                case .week: WeekView(model: week) { showsSearch = true }
                case .month: MonthView(model: month) { showsSearch = true }
                }
            }
            .navigationTitle("Calendar")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                }
                .task(id: mode) { await loadIfNeeded() }
                .refreshable { await reload() }
                .navigationDestination(for: String.self) { id in
                    if let entry = library.entry(id) {
                        TitleDetailView(entry: entry, api: api, library: library, lists: lists)
                    }
                }
                .sheet(isPresented: $showsSearch) {
                    SearchView(api: api, library: library, lists: lists)
                }
                .safeAreaInset(edge: .bottom) {
                    ProblemBanner(message: feed.problem) { feed.problem = nil }
                }
                .background(Color(.paper))
        }
    }

    private func loadIfNeeded() async {
        switch mode {
        case .week: await week.loadIfNeeded()
        case .month: await month.loadIfNeeded()
        }
    }

    private func reload() async {
        switch mode {
        case .week: await week.load()
        case .month: await month.load()
        }
    }
}

// MARK: Previews

#Preview("Mac · month", traits: .fixedLayout(width: 1280, height: 800)) {
    CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
        .defaultAppStorage(.preview(mode: .month))
}

#Preview("Mac · month · dark", traits: .fixedLayout(width: 1280, height: 800)) {
    CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
        .defaultAppStorage(.preview(mode: .month))
        .preferredColorScheme(.dark)
}

#Preview("Mac · week", traits: .fixedLayout(width: 1280, height: 720)) {
    CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
        .defaultAppStorage(.preview(mode: .week))
}

#if os(iOS)
    #Preview("iPhone · month") {
        CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
            .defaultAppStorage(.preview(mode: .month))
            .environment(\.horizontalSizeClass, .compact)
    }

    #Preview("iPhone · week · dark") {
        CalendarScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: .sample)
            .defaultAppStorage(.preview(mode: .week))
            .environment(\.horizontalSizeClass, .compact)
            .preferredColorScheme(.dark)
    }
#endif

#Preview("Empty") {
    CalendarScreen(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil), feed: CalendarFeed(preview: [])
    )
}

private extension UserDefaults {
    static func preview(mode: CalendarScreen.Mode) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "calendar-preview-\(mode.rawValue)") ?? .standard
        defaults.set(mode.rawValue, forKey: "calendar.mode")
        return defaults
    }
}
