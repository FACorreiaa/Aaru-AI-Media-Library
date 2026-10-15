import AaruAPI
import SwiftUI

/// APP-010: what airs this week from the user's own shows (DESIGN.md §14). The full seven-day
/// grid on Mac and iPad; a day pager with the same cells on iPhone.
struct WeekView: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @State private var model: WeekModel
    /// The day the iPhone pager shows.
    @State private var selection: Date
    @State private var showsSearch = false

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        private var isWide: Bool {
            sizeClass == .regular
        }
    #else
        private let isWide = true
    #endif

    init(api: Client?, library: LibraryModel, lists: ListsModel, model: WeekModel? = nil) {
        self.api = api
        self.library = library
        self.lists = lists
        let model = model ?? WeekModel(api: api, library: library)
        _model = State(initialValue: model)
        let today = model.calendar.startOfDay(for: .now)
        _selection = State(initialValue: model.days.contains(today) ? today : model.start)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Week")
                .toolbar { toolbar }
                .task { await model.load() }
                .refreshable { await model.load() }
                .navigationDestination(for: String.self) { id in
                    if let entry = library.entry(id) {
                        TitleDetailView(entry: entry, api: api, library: library, lists: lists)
                    }
                }
                .sheet(isPresented: $showsSearch) {
                    SearchView(api: api, library: library, lists: lists)
                }
                .safeAreaInset(edge: .bottom) {
                    ProblemBanner(message: model.problem) { model.problem = nil }
                }
                .background(Color(.paper))
        }
    }

    @ViewBuilder private var content: some View {
        if !model.hasLoaded, model.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isEmptyWeek {
            ContentUnavailableView {
                Label("Nothing from your shows airs this week.", systemImage: "calendar")
            } description: {
                Text("Add shows you follow and their new episodes appear here.")
            } actions: {
                Button("Search") { showsSearch = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if isWide {
            WeekGridView(model: model)
        } else {
            WeekDayPager(model: model, selection: $selection)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Previous day", systemImage: "chevron.left") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Today") { goToToday() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(model.containsToday && (isWide || model.calendar.isDateInToday(selection)))
            Button("Next day", systemImage: "chevron.right") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    /// The grid moves its window a day; the pager moves the selected day and drags the window
    /// along only when it leaves the seven.
    private func step(_ delta: Int) {
        Task {
            if isWide {
                await model.step(days: delta)
            } else if let next = model.calendar.date(byAdding: .day, value: delta, to: selection) {
                await model.reveal(next)
                withAnimation(.snappy) { selection = model.calendar.startOfDay(for: next) }
            }
        }
    }

    private func goToToday() {
        Task {
            await model.goToToday()
            withAnimation(.snappy) { selection = model.calendar.startOfDay(for: .now) }
        }
    }
}

// MARK: Previews

private extension WeekModel {
    /// A week that looks like a real one: premieres, a finale, watched episodes, a date-only
    /// air date, missing art.
    static var sample: WeekModel {
        let calendar = Calendar.current
        let start = weekStart(of: .now, in: calendar)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: day, to: start) ?? start
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
        }
        func dateOnly(_ day: Int) -> Date {
            let local = calendar.dateComponents([.year, .month, .day], from: at(day, 12))
            return utcCalendar.date(from: local) ?? start
        }
        func show(_ name: String, _ network: String?, backdrop: String? = nil) -> Components.Schemas.TitleSummary {
            .init(
                id: UUID().uuidString, _type: .show, title: name,
                backdropUrl: backdrop, network: network, isAnime: false, ids: .init()
            )
        }
        func entry(
            _ title: Components.Schemas.TitleSummary, _ season: Int, _ number: Int, _ name: String, _ airsAt: Date,
            exact: Bool = true, watched: Bool = false, kind: CalendarEntry.KindPayload = .regular
        ) -> CalendarEntry {
            .init(
                libraryItemId: title.id, title: title, season: season, number: number, episodeName: name,
                airsAt: airsAt, airTimeKnown: exact, watched: watched, kind: kind
            )
        }
        let severance = show("Severance", "Apple TV+")
        let andor = show("Andor", "Disney+")
        let frieren = show("Frieren: Beyond Journey's End", "Crunchyroll")
        let bear = show("The Bear", "FX")
        let slow = show("Slow Horses", "Apple TV+")
        let pitt = show("The Pitt", "HBO Max")
        return WeekModel(preview: [
            entry(severance, 2, 1, "Hello, Ms. Cobel", at(0, 3), kind: .premiere),
            entry(pitt, 1, 14, "8:00 P.M.", at(0, 21), watched: true),
            entry(andor, 2, 4, "Ever Been to Ghorman?", at(1, 3)),
            entry(frieren, 2, 1, "The Journey North", at(2, 16, 30), kind: .premiere),
            entry(bear, 4, 10, "Forever", dateOnly(3), exact: false, kind: .finale),
            entry(slow, 5, 3, "Missing Persons", at(3, 9)),
            entry(pitt, 1, 15, "9:00 P.M.", at(4, 21)),
            entry(severance, 2, 2, "Goodbye, Mrs. Selvig", at(5, 3)),
            entry(show("Pluribus", nil), 1, 1, "We Is Us", at(6, 3), kind: .premiere),
        ], start: start, calendar: calendar)
    }
}

#Preview("Mac grid", traits: .fixedLayout(width: 1280, height: 720)) {
    WeekView(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample)
}

#Preview("Mac grid · dark", traits: .fixedLayout(width: 1280, height: 720)) {
    WeekView(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample)
        .preferredColorScheme(.dark)
}

#if os(iOS)
    #Preview("iPhone pager") {
        WeekView(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample)
            .environment(\.horizontalSizeClass, .compact)
    }

    #Preview("iPhone pager · dark") {
        WeekView(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample)
            .environment(\.horizontalSizeClass, .compact)
            .preferredColorScheme(.dark)
    }
#endif

#Preview("Empty week") {
    WeekView(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: WeekModel(preview: [], start: .now))
}
