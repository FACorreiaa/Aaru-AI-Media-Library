import AaruAPI
import Charts
import SwiftUI

// Insights' charts and lists, out of `StatsPanel.swift` to keep it under the file limit.

/// Hours per bucket: days of a month or rolling window, months of a year, or years of all time.
/// A rolling window keeps a thin track under empty days, so the week still reads as seven.
struct ActivityChart: View {
    let stats: Stats
    @ScaledMetric(relativeTo: .body) private var height = 180

    private var isRolling: Bool {
        stats.span == .last7 || stats.span == .last30
    }

    private var track: Double {
        max(0.05, Double(stats.buckets.map(\.minutes).max() ?? 0) / 60 * 0.03)
    }

    var body: some View {
        Chart(stats.buckets, id: \.start) { bucket in
            let empty = isRolling && bucket.minutes == 0
            BarMark(
                x: .value("Period", bucket.start),
                y: .value("Hours", empty ? track : Double(bucket.minutes) / 60)
            )
            .foregroundStyle(empty ? Color(.muted).opacity(AaruAlpha.ghost) : Color(.accent))
            .cornerRadius(3)
            .accessibilityLabel(label(bucket.start, full: true))
            .accessibilityValue("\(hoursValue(minutes: bucket.minutes)) hours")
        }
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                AxisValueLabel {
                    if let start = value.as(String.self) {
                        Text(label(start, full: false))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: height)
    }

    /// Every bucket for months, years and a week; every fifth day across 30 days or a month so
    /// labels do not collide.
    private var axisValues: [String] {
        let starts = stats.buckets.map(\.start)
        guard stats.span == .month || stats.span == .last30 else { return starts }
        return starts.enumerated().filter { $0.offset % 5 == 0 }.map(\.element)
    }

    private func label(_ start: String, full: Bool) -> String {
        let parts = start.split(separator: "-").compactMap { Int($0) }
        switch stats.span {
        case .month, .last30:
            return full ? RecapDeck.dayLabel(start) : "\(parts.count > 2 ? parts[2] : 1)"
        case .last7:
            return full ? RecapDeck.dayLabel(start) : weekdayInitial(parts)
        case .year:
            let name = RecapDeck.months[max(0, min(11, (parts.count > 1 ? parts[1] : 1) - 1))]
            return full ? name : String(name.prefix(1))
        case .all:
            return "\(parts.first ?? stats.year)"
        }
    }

    /// "M", "T", …: the weekday of a bare `YYYY-MM-DD`, read in UTC so no zone shifts it.
    private func weekdayInitial(_ parts: [Int]) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return "" }
        return calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }
}

struct KindBreakdown: View {
    let kinds: [Components.Schemas.StatsKind]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(kinds, id: \.kind) { entry in
                let kind = MediaKind(entry.kind)
                HStack(spacing: 12) {
                    Image(systemName: kind.symbol)
                        .frame(width: 24)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(kind.label)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text(detail(entry))
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                if entry.kind != kinds.last?.kind {
                    Divider()
                }
            }
        }
    }

    private func detail(_ entry: Components.Schemas.StatsKind) -> String {
        // Albums have no episodes and no minutes: only how many were listened to.
        if entry.kind == .album {
            return entry.finished == 1 ? "1 album listened" : "\(entry.finished) albums listened"
        }
        var parts = ["\(entry.finished) finished"]
        if entry.episodes > 0 {
            parts.append(entry.episodes == 1 ? "1 episode" : "\(entry.episodes) episodes")
        }
        if entry.minutes > 0 {
            parts.append(durationLabel(minutes: entry.minutes))
        }
        return entry.finished == 0 && parts.count == 1 ? "Nothing yet" : parts.joined(separator: " · ")
    }
}

struct TopTitles: View {
    let titles: [StatsTitle]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, entry in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.aaruDisplay(.title3, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 22)
                        .foregroundStyle(Color(.muted))
                    PosterView(url: entry.title.posterURL, kind: entry.title.mediaKind)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title.title).font(.body.weight(.medium)).lineLimit(2)
                        Text(detail(entry))
                            .font(.footnote)
                            .foregroundStyle(Color(.muted))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func detail(_ entry: StatsTitle) -> String {
        [
            entry.episodes > 0 ? (entry.episodes == 1 ? "1 episode" : "\(entry.episodes) episodes") : nil,
            entry.minutes > 0 ? durationLabel(minutes: entry.minutes) : nil,
        ].compactMap(\.self).joined(separator: " · ")
    }
}

/// Ten bins on the 1–10 scale; a half star rounds up.
struct RatingsHistogram: View {
    let ratings: Components.Schemas.StatsRatings
    @ScaledMetric(relativeTo: .body) private var height = 140

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            if let mean = ratings.mean {
                Text(
                    "Average \(RecapDeck.ratingLabel(mean)) from "
                        + (ratings.count == 1 ? "1 rating" : "\(ratings.count) ratings")
                )
                .font(.footnote)
                .foregroundStyle(Color(.muted))
            }
            Chart(Array(ratings.distribution.enumerated()), id: \.offset) { index, count in
                BarMark(
                    x: .value("Rating", "\(index + 1)"),
                    y: .value("Titles", count)
                )
                .foregroundStyle(Color(.gold))
                .cornerRadius(3)
                .accessibilityLabel("Rated \(index + 1)")
                .accessibilityValue(count == 1 ? "1 title" : "\(count) titles")
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: height)
            if let highest = ratings.highest, let rating = ratings.highestRating {
                Text("Highest: \(highest.title), \(RecapDeck.ratingLabel(rating))")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
        }
    }
}
