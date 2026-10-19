import Algorithms
import SwiftUI
import WidgetKit

/// Airing countdown (WID-003): the next episode of a tracked show. Timeline entries sit at each
/// air time (it flips to "Out now") and at midnight ("Tomorrow" becomes "Today"), so it stays
/// right with the app closed.
struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AaruCountdown", provider: CountdownProvider()) { entry in
            CountdownView(entry: entry)
                .aaruWidgetBackground()
        }
        .configurationDisplayName("Next Episode")
        .description("Counts down to the next episode of a show you follow.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
            [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
            [.systemSmall]
        #endif
    }
}

/// An episode stays "Out now" for this long after it airs.
private let outNowWindow: TimeInterval = 3600

struct CountdownProvider: TimelineProvider {
    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshotStore.load()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let now = Date.now
        let calendar = WidgetSnapshot.weekCalendar
        var dates: Set<Date> = [now]
        for airing in snapshot?.airings ?? [] where airing.airTimeKnown && airing.airsAt > now {
            dates.insert(airing.airsAt)
            dates.insert(airing.airsAt.addingTimeInterval(outNowWindow))
        }
        // Midnights, so day labels move on.
        var midnight = calendar.startOfDay(for: now)
        for _ in 0 ..< 3 {
            midnight = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight
            dates.insert(midnight)
        }
        let entries = dates.min(count: 24).map { SnapshotEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// What the countdown shows at one moment.
struct CountdownState {
    let airing: WidgetSnapshot.Airing
    let isOut: Bool

    init?(entry: SnapshotEntry) {
        guard let snapshot = entry.snapshot else { return nil }
        let now = entry.date
        if let out = snapshot.airings.first(where: { airing in
            !airing.watched && airing.airTimeKnown
                && airing.airsAt <= now && now < airing.airsAt.addingTimeInterval(outNowWindow)
        }) {
            airing = out
            isOut = true
        } else if let next = snapshot.upcoming(at: now).first {
            airing = next
            isOut = false
        } else {
            return nil
        }
    }

    /// "Today", "Tomorrow", "Thursday" for date-only episodes; "Thu 21:00" for exact ones further
    /// than a day out.
    func dayLabel(at now: Date) -> String {
        let calendar = WidgetSnapshot.weekCalendar
        let today = WidgetSnapshot.DayKey(calendar.dateComponents([.year, .month, .day], from: now))
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrow = WidgetSnapshot.DayKey(calendar.dateComponents([.year, .month, .day], from: tomorrowDate))
        switch airing.day(in: calendar) {
        case today: return "Today"
        case tomorrow: return "Tomorrow"
        default:
            let reader = airing.airTimeKnown ? calendar : WidgetSnapshot.utc
            let style = Date.FormatStyle(date: .omitted, time: .omitted, timeZone: reader.timeZone).weekday(.wide)
            return airing.airsAt.formatted(style)
        }
    }

    /// Exact and under a day away: a live relative countdown.
    func isCountingDown(at now: Date) -> Bool {
        !isOut && airing.airTimeKnown && airing.airsAt.timeIntervalSince(now) < 86400
    }
}

struct CountdownView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let state = CountdownState(entry: entry) {
            content(state)
                .widgetURL(WidgetLink.title(state.airing.libraryItemId))
        } else if entry.snapshot == nil {
            SetUpView(compact: family != .systemSmall)
        } else {
            Text("Nothing airing soon")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    @ViewBuilder
    private func content(_ state: CountdownState) -> some View {
        switch family {
        #if os(iOS)
            case .accessoryInline:
                when(state)
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text(state.airing.episodeCode)
                        .font(.system(size: 10, weight: .semibold))
                    when(state)
                        .font(.system(size: 11))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.airing.title).font(.headline).lineLimit(1)
                    Text(state.airing.episodeCode).font(.caption)
                    when(state).font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("Next episode")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.brand)
                Text(state.airing.title)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(state.airing.episodeCode + (state.airing.episodeName.map { " · \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                when(state)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(state.isOut ? Palette.gold : Palette.brand)
                if let network = state.airing.network {
                    Text(network)
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// "Out now", "In 2 hr, 14 min" (live), "Thursday", or "Thursday 21:00".
    private func when(_ state: CountdownState) -> Text {
        if state.isOut {
            return Text("Out now")
        }
        if state.isCountingDown(at: entry.date) {
            return Text("In \(state.airing.airsAt, style: .relative)")
        }
        let day = state.dayLabel(at: entry.date)
        guard state.airing.airTimeKnown else { return Text(day) }
        return Text("\(day) \(state.airing.airsAt.formatted(date: .omitted, time: .shortened))")
    }
}

#Preview(as: .systemSmall) {
    CountdownWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}
