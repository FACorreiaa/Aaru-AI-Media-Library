import SwiftUI

/// Month mode: the grid with the agenda beside it on Mac and iPad, below it on iPhone.
struct MonthView: View {
    let model: MonthModel
    var onSearch: () -> Void

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
            if isWide {
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        MonthSwitcher(model: model)
                        MonthGridView(model: model, style: .posters)
                    }
                    .padding(16)
                    Divider()
                    AgendaList(model: model, onSearch: onSearch)
                        .frame(width: 330)
                }
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        MonthSwitcher(model: model)
                        MonthGridView(model: model, style: .dots)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    Divider()
                    AgendaList(model: model, onSearch: onSearch)
                }
            }
        }
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Previous month", systemImage: "chevron.left") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Today") { Task { await model.goToToday() } }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(model.showsToday)
            Button("Next month", systemImage: "chevron.right") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    private func step(_ delta: Int) {
        Task { await model.step(months: delta) }
    }
}
