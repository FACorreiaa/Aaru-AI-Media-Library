import SwiftUI

/// Week mode (APP-010, DESIGN.md §14): the full seven-day grid on Mac and iPad; a day pager with
/// the same cells on iPhone. `CalendarScreen` owns navigation and loading.
struct WeekView: View {
    let model: WeekModel
    var onSearch: () -> Void
    /// Set while a filter is on: empty states offer "Clear filters" (UX-067).
    var onClearFilters: (() -> Void)?

    /// The day the iPhone pager shows.
    @State private var selection: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        private var isWide: Bool {
            sizeClass == .regular
        }
    #else
        private let isWide = true
    #endif

    init(model: WeekModel, onSearch: @escaping () -> Void, onClearFilters: (() -> Void)? = nil) {
        self.model = model
        self.onSearch = onSearch
        self.onClearFilters = onClearFilters
        let today = model.calendar.startOfDay(for: .now)
        _selection = State(initialValue: model.days.contains(today) ? today : model.start)
    }

    var body: some View {
        content
            .toolbar { toolbar }
    }

    @ViewBuilder private var content: some View {
        if let failure = model.loadProblem {
            LoadFailedView(title: "The calendar didn't load", message: failure) { await model.load() }
        } else if !model.isLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isEmptyWeek {
            CalendarEmptyState(
                title: "Nothing from your shows airs this week",
                detail: "Add shows you follow and their new episodes appear here.",
                onSearch: onSearch, onClearFilters: onClearFilters
            )
        } else if isWide {
            WeekGridView(model: model)
        } else {
            WeekDayPager(model: model, selection: $selection, filtersActive: onClearFilters != nil)
        }
    }

    /// Wide: a day or a week at a time. Compact: Today and the week arrows; days by swipe
    /// (UX-091). Arrows carry ⌘ so they never take a plain arrow key from a list or a field.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Previous week", systemImage: "chevron.left.2") { step(-7) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            if isWide {
                Button("Previous day", systemImage: "chevron.left") { step(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }
            Button("Today") { goToToday() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(model.containsToday && (isWide || model.calendar.isDateInToday(selection)))
            if isWide {
                Button("Next day", systemImage: "chevron.right") { step(1) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            Button("Next week", systemImage: "chevron.right.2") { step(7) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        }
    }

    private var stepAnimation: Animation? {
        reduceMotion ? nil : .snappy
    }

    /// The grid moves its window; the pager moves the selected day and drags the window along
    /// only when it leaves the seven.
    private func step(_ delta: Int) {
        Task {
            if isWide {
                await model.step(days: delta)
            } else if let next = model.calendar.date(byAdding: .day, value: delta, to: selection) {
                await model.reveal(next)
                withAnimation(stepAnimation) { selection = model.calendar.startOfDay(for: next) }
            }
        }
    }

    private func goToToday() {
        Task {
            await model.goToToday()
            withAnimation(stepAnimation) { selection = model.calendar.startOfDay(for: .now) }
        }
    }
}

/// The calendar's empty state: "nothing airs" with Search, or, while a filter hides things, "No
/// episodes match these filters" with Clear filters (UX-067).
struct CalendarEmptyState: View {
    let title: String
    let detail: String
    var onSearch: (() -> Void)?
    var onClearFilters: (() -> Void)?

    var body: some View {
        if let onClearFilters {
            ContentUnavailableView {
                Label("No episodes match these filters", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Clear filters", action: onClearFilters)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label(title, systemImage: "calendar")
            } description: {
                Text(detail)
            } actions: {
                if let onSearch {
                    Button("Search", action: onSearch)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
