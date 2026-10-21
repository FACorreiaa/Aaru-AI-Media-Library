import SwiftUI

/// Week mode (APP-010, DESIGN.md §14): the full seven-day grid on Mac and iPad; a day pager with
/// the same cells on iPhone. `CalendarScreen` owns navigation and loading.
struct WeekView: View {
    let model: WeekModel
    var onSearch: () -> Void

    /// The day the iPhone pager shows.
    @State private var selection: Date

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        private var isWide: Bool {
            sizeClass == .regular
        }
    #else
        private let isWide = true
    #endif

    init(model: WeekModel, onSearch: @escaping () -> Void) {
        self.model = model
        self.onSearch = onSearch
        let today = model.calendar.startOfDay(for: .now)
        _selection = State(initialValue: model.days.contains(today) ? today : model.start)
    }

    var body: some View {
        content
            .toolbar { toolbar }
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
                Button("Search", action: onSearch)
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
            Button("Previous week", systemImage: "chevron.left.2") { step(-7) }
                .keyboardShortcut(.pageUp, modifiers: [])
            Button("Previous day", systemImage: "chevron.left") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Today") { goToToday() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(model.containsToday && (isWide || model.calendar.isDateInToday(selection)))
            Button("Next day", systemImage: "chevron.right") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Next week", systemImage: "chevron.right.2") { step(7) }
                .keyboardShortcut(.pageDown, modifiers: [])
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
