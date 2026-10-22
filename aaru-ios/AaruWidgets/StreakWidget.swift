import AaruCore
import SwiftUI
import WidgetKit

/// Streak (WID-007, DESIGN.md §16): a flame, the day count and the last seven days as bars. Its
/// timeline holds the next two local midnights, read by AaruCore's `Streak` rule, so a streak
/// that was not kept ends at midnight with the app closed.
struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.streakWidgetKind, provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
                .aaruWidgetBackground()
        }
        .configurationDisplayName("Streak")
        .description("Your streak and the last seven days.")
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

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: WidgetSnapshot.StreakState?

    /// The local day of this entry, `yyyy-MM-dd`, on the device's clock.
    var today: String {
        Streak.localDate(date, in: .current)
    }
}

struct StreakProvider: TimelineProvider {
    func placeholder(in _: Context) -> StreakEntry {
        StreakEntry(date: .now, streak: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: .now, streak: context.isPreview ? .sample : WidgetSnapshotStore.load()?.streak))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let streak = WidgetSnapshotStore.load()?.streak
        let now = Date.now
        let calendar = Calendar.current
        var dates = [now]
        var midnight = calendar.startOfDay(for: now)
        for _ in 0 ..< 2 {
            midnight = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight
            dates.append(midnight)
        }
        completion(Timeline(entries: dates.map { StreakEntry(date: $0, streak: streak) }, policy: .atEnd))
    }
}

struct StreakWidgetView: View {
    let entry: StreakEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let streak = entry.streak {
            content(streak.summary(on: entry.today), week: streak.week(ending: entry.today))
        } else {
            SetUpView(compact: family != .systemSmall)
        }
    }

    @ViewBuilder
    private func content(_ summary: StreakSummary, week: [(date: String, active: Bool)]) -> some View {
        switch family {
        #if os(iOS)
            case .accessoryInline:
                Label(Self.days(summary.current), systemImage: "flame")
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: "flame")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(summary.current)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Streak, \(Self.days(summary.current))")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 4) {
                    Label(Self.days(summary.current), systemImage: "flame")
                        .font(.headline)
                    Bars(week: week, active: .primary, idle: .secondary.opacity(0.4))
                        .frame(height: 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        default:
            small(summary, week: week)
        }
    }

    private func small(_ summary: StreakSummary, week: [(date: String, active: Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: summary.current > 0 ? "flame.fill" : "flame")
                .font(.title3)
                .foregroundStyle(summary.current > 0 ? Palette.brand : Palette.muted)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text("\(summary.current)")
                .font(.custom("Newsreader-Medium", size: 40, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.6)
            Text("day streak")
                .font(.caption)
                .foregroundStyle(Palette.muted)
            Bars(week: week, active: Palette.brand, idle: Palette.muted.opacity(0.3))
                .frame(height: 8)
            Text(summary.today || summary.current == 0 ? " " : "Tick something today")
                .font(.caption2)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Streak, \(Self.days(summary.current)). Active on \(week.count { $0.active }) of the last 7 days."
        )
    }

    static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}

/// Seven bars, oldest first.
private struct Bars<Active: ShapeStyle, Idle: ShapeStyle>: View {
    let week: [(date: String, active: Bool)]
    let active: Active
    let idle: Idle

    var body: some View {
        HStack(spacing: 3) {
            ForEach(week, id: \.date) { day in
                if day.active {
                    Capsule().fill(active)
                } else {
                    Capsule().fill(idle)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

extension WidgetSnapshot.StreakState {
    /// The gallery and previews: twelve days, today in.
    static var sample: Self {
        let today = Streak.localDate(.now, in: .current)
        let active = (0 ..< 7).compactMap { Streak.adding(-$0, to: today) }
        return Self(current: 12, longest: 21, lastActive: today, active: active)
    }
}

#Preview(as: .systemSmall) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: .sample)
}
