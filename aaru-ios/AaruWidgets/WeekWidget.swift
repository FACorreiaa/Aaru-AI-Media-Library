import SwiftUI
import WidgetKit

/// The CAT week in miniature (WID-004): seven Monday-first columns, up to three episodes a day,
/// watched dimmed, today highlighted. Cells open the show in the app.
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AaruWeek", provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
                .aaruWidgetBackground()
        }
        .configurationDisplayName("This Week")
        .description("What airs this week from the shows you follow.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

struct WeekProvider: TimelineProvider {
    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshotStore.load()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let calendar = WidgetSnapshot.weekCalendar
        // Today's highlight moves at midnight.
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        completion(Timeline(
            entries: [SnapshotEntry(date: .now, snapshot: snapshot), SnapshotEntry(date: midnight, snapshot: snapshot)],
            policy: .atEnd
        ))
    }
}

/// The seven days of the entry's week, each with its episodes in air order.
struct WeekColumns {
    struct Day: Identifiable {
        let key: WidgetSnapshot.DayKey
        let date: Date
        let isToday: Bool
        let airings: [WidgetSnapshot.Airing]

        var id: WidgetSnapshot.DayKey {
            key
        }
    }

    let days: [Day]

    init(snapshot: WidgetSnapshot, at now: Date, calendar: Calendar = WidgetSnapshot.weekCalendar) {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let today = WidgetSnapshot.DayKey(calendar.dateComponents([.year, .month, .day], from: now))
        let byDay = Dictionary(grouping: snapshot.airings) { $0.day(in: calendar) }
        days = (0 ..< 7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = WidgetSnapshot.DayKey(calendar.dateComponents([.year, .month, .day], from: date))
            return Day(key: key, date: date, isToday: key == today, airings: byDay[key] ?? [])
        }
    }
}

struct WeekWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    /// Episodes shown per day before "+N".
    private let perDay = 3

    var body: some View {
        if let snapshot = entry.snapshot {
            let columns = WeekColumns(snapshot: snapshot, at: entry.date)
            VStack(alignment: .leading, spacing: 6) {
                Text("This week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.accent))
                    .widgetAccentable()
                HStack(alignment: .top, spacing: 4) {
                    ForEach(columns.days) { day in
                        DayColumn(day: day, perDay: perDay, roomy: family == .systemExtraLarge)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        } else {
            SetUpView()
        }
    }
}

private struct DayColumn: View {
    let day: WeekColumns.Day
    let perDay: Int
    let roomy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.date.formatted(.dateTime.day()))
                    .font(.headline.monospacedDigit())
                Text(day.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(day.isToday ? Color(.onAccent) : Color(.ink))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                day.isToday ? Color(.accent) : .clear,
                in: .rect(cornerRadius: AaruRadius.thumb, style: .continuous)
            )
            ForEach(day.airings.prefix(perDay)) { airing in
                Link(destination: WidgetLink.title(airing.libraryItemId) ?? URL(fileURLWithPath: "/")) {
                    WeekCellView(airing: airing, roomy: roomy)
                }
            }
            if day.airings.count > perDay {
                Text("+\(day.airings.count - perDay)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(.muted))
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            day.isToday ? Color(.accent).opacity(AaruAlpha.tint) : Color(.surface).opacity(AaruAlpha.half),
            in: .rect(cornerRadius: AaruRadius.row, style: .continuous)
        )
    }
}

private struct WeekCellView: View {
    let airing: WidgetSnapshot.Airing
    let roomy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(airing.title)
                .font((roomy ? Font.caption : .caption2).weight(.semibold))
                .foregroundStyle(Color(.accent))
                .lineLimit(2)
            Text(airing.episodeCode)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color(.ink))
            if roomy, let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if airing.kind != .regular {
                Rectangle()
                    .fill(airing.kind == .finale ? Color(.gold) : Color(.accent))
                    .frame(width: 2)
            }
        }
        .opacity(airing.watched ? 0.4 : 1)
    }

    /// "HBO · 21:00", time only when exact.
    private var detail: String? {
        let time = airing.airTimeKnown ? airing.airsAt.formatted(date: .omitted, time: .shortened) : nil
        let parts = [airing.network, time].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview(as: .systemLarge) {
    WeekWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}
