import SwiftUI

/// Mac and iPad: the seven days side by side, Pogdesign CAT's dense week, one shared scroll.
struct WeekGridView: View {
    let model: WeekModel

    /// Seven columns fit a 13-inch iPad in portrait; narrower windows scroll sideways.
    private static let minColumnWidth: CGFloat = 128
    private static let spacing: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.width - 32
            let width = max(Self.minColumnWidth, (available - Self.spacing * 6) / 7)
            let fits = width * 7 + Self.spacing * 6 <= available + 0.5
            // One scroll view: nesting a second one (even with no axes) applied the navigation
            // bar's safe-area inset twice and left an empty band above the day headers on iPad.
            ScrollView(fits ? .vertical : [.vertical, .horizontal]) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        columns(width: width)
                    } header: {
                        headers(width: width)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func headers(width: CGFloat) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(model.days, id: \.self) { day in
                WeekDayHeader(date: day, isToday: model.isToday(day))
                    .frame(width: width)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.paper))
    }

    private func columns(width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(model.days, id: \.self) { day in
                WeekColumn(model: model, day: day)
                    .frame(width: width)
            }
        }
    }
}

/// One day's cells, today tinted.
private struct WeekColumn: View {
    let model: WeekModel
    let day: Date

    var body: some View {
        let entries = model.entries(on: day)
        LazyVStack(spacing: 8) {
            ForEach(entries, id: \.cellID) { entry in
                NavigationLink(value: entry.libraryItemId) {
                    WeekCell(entry: entry, isPending: model.pending.contains(entry.cellID)) {
                        Task { await model.toggle(entry) }
                    }
                }
                .buttonStyle(.plain)
            }
            if entries.isEmpty {
                Text("Nothing")
                    .font(.caption)
                    .foregroundStyle(Color(.muted).opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
        .padding(6)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            model.isToday(day) ? Color.accentColor.opacity(0.08) : Color(.ink).opacity(0.03),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}

/// "15 THU": the big day number CAT made famous, today in the accent.
struct WeekDayHeader: View {
    let date: Date
    let isToday: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(date.formatted(.dateTime.day()))
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isToday ? Color(.paper) : Color(.ink))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isToday ? Color.accentColor : Color(.surface), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (isToday ? ", today" : ""))
    }
}
