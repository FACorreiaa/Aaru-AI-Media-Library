import AaruAPI
import SwiftUI

/// `StreakBar` (VIEWS.md): the streak and the last seven days as ticks, and on Home the level and
/// points to the next level beside it. Calm: no countdown, one quiet line when today is still open.
struct StreakBar: View {
    let progress: AchievementProgress
    /// Home shows the level beside the streak and a chevron to Achievements.
    var showsLevel = true
    var isLink = false

    private var streak: Components.Schemas.StreakState {
        progress.streak
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            HStack(spacing: AaruSpace.small) {
                Image(systemName: streak.current > 0 ? "flame.fill" : "flame")
                    .font(.title3)
                    .foregroundStyle(streak.current > 0 ? Color(.accent) : Color(.muted))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(StreakWords.headline(streak.current))
                        .font(.aaruDisplay(.title3, weight: .semibold))
                        .monospacedDigit()
                    Text(StreakWords.note(streak))
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                }
                Spacer(minLength: 8)
                if isLink {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.muted))
                        .accessibilityHidden(true)
                }
            }
            WeekTicks(days: streak.days)
            if showsLevel {
                LevelLine(progress: progress)
            }
        }
        .panel()
        .contentShape(.rect(cornerRadius: AaruRadius.panel, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(isLink ? "Opens Achievements" : "")
    }
}

/// Seven ticks, oldest first, each with its weekday's initial; today's is outlined.
private struct WeekTicks: View {
    let days: [Components.Schemas.StreakDayState]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                let isToday = index == days.count - 1
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.active ? Color(.accent) : Color(.line))
                        .frame(height: 6)
                        .overlay {
                            if isToday, !day.active {
                                RoundedRectangle(cornerRadius: 3).strokeBorder(Color(.accent), lineWidth: 1)
                            }
                        }
                    Text(StreakWords.initial(day.date))
                        .font(.caption2)
                        .foregroundStyle(isToday ? Color(.ink) : Color(.muted))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StreakWords.weekLabel(days))
    }
}

/// "Level 4", a thin bar to the next level, and "120 to level 5".
struct LevelLine: View {
    let progress: AchievementProgress

    private var fraction: Double {
        let span = progress.nextLevelAt - progress.levelStart
        guard span > 0 else { return 0 }
        return Double(progress.total - progress.levelStart) / Double(span)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Level \(progress.level)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\((progress.nextLevelAt - progress.total).formatted()) to level \(progress.level + 1)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color(.muted))
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .accessibilityHidden(true)
        }
    }
}

/// How the streak reads, the same words as the web's.
enum StreakWords {
    static func headline(_ current: Int) -> String {
        switch current {
        case 0: "No streak yet"
        case 1: "1-day streak"
        default: "\(current.formatted())-day streak"
        }
    }

    /// Today done, today still open, or the longest so far.
    static func note(_ streak: Components.Schemas.StreakState) -> String {
        if streak.current > 0, !streak.today {
            return "Tick something today to keep it"
        }
        if streak.longest > streak.current {
            return "Longest: \(streak.longest.formatted()) days"
        }
        return streak.current > 0 ? "Today is in" : "Tick an episode or finish something to start one"
    }

    /// The weekday's initial for a `yyyy-MM-dd` date, read at noon UTC so it is the same anywhere.
    static func initial(_ date: String) -> String {
        guard let day = try? Date(date + "T12:00:00Z", strategy: .iso8601) else { return "" }
        var style = Date.FormatStyle.dateTime.weekday(.narrow)
        style.timeZone = .gmt
        return day.formatted(style)
    }

    static func weekLabel(_ days: [Components.Schemas.StreakDayState]) -> String {
        let active = days.count(where: \.active)
        return "Active on \(active) of the last \(days.count) days"
    }
}
