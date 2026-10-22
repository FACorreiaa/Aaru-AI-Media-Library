import SwiftUI

/// Month mode: the grid with the agenda beside it on Mac and iPad, below it on iPhone.
struct MonthView: View {
    let model: MonthModel
    var onSearch: () -> Void
    /// Set while a filter is on: empty states offer "Clear filters" (UX-067).
    var onClearFilters: (() -> Void)?
    /// "Open show" from the iPhone day sheet's episode sheet: pushes on the calendar's stack.
    var onOpenShow: (String) -> Void = { _ in }

    /// iPhone: the tapped day, open as a sheet (CAL-003).
    @State private var openDay: Date?

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        private var isWide: Bool {
            sizeClass == .regular
        }
    #else
        private let isWide = true
    #endif

    var body: some View {
        Group {
            if let failure = model.loadProblem {
                LoadFailedView(title: "The calendar didn't load", message: failure) { await model.load() }
            } else if isWide {
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        MonthSwitcher(model: model)
                        MonthGridView(model: model, style: .posters)
                    }
                    .padding(16)
                    Divider()
                    AgendaList(model: model, onSearch: onSearch, onClearFilters: onClearFilters)
                        .frame(width: 330)
                }
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        MonthSwitcher(model: model)
                        MonthGridView(model: model, style: .compact) { openDay = $0 }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    Divider()
                    AgendaList(model: model, onSearch: onSearch, onClearFilters: onClearFilters)
                }
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $openDay.isPresent) {
            if let openDay {
                DaySheet(day: openDay, feed: model.feed) { id in
                    self.openDay = nil
                    onOpenShow(id)
                }
            }
        }
    }

    /// ⌘← and ⌘→ step the month; plain arrows stay with the grid and lists.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Previous month", systemImage: "chevron.left") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Today") { Task { await model.goToToday() } }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(model.showsToday)
            Button("Next month", systemImage: "chevron.right") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
        }
    }

    private func step(_ delta: Int) {
        Task { await model.step(months: delta) }
    }
}
