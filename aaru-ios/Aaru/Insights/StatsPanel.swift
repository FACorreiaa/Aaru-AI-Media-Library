import AaruAPI
import Charts
import SwiftUI

/// `StatsPanel`: one period's numbers. Totals, time per day/month/year, what kinds, top titles,
/// the longest run and how the user rated. Static on purpose: like the Recap, no number animates.
struct StatsPanel: View {
    let stats: Stats

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let from = stats.from, let until = stats.until {
                Text("\(RecapDeck.dayLabel(from)) – \(RecapDeck.dayLabel(until)) · Private to you")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            TotalsGrid(totals: stats.totals, prior: stats.prior)
            if stats.buckets.contains(where: { $0.minutes > 0 }) {
                PanelSection(title: "Time") { ActivityChart(stats: stats) }
            }
            if stats.byKind.contains(where: { $0.minutes > 0 || $0.episodes > 0 || $0.finished > 0 }) {
                PanelSection(title: "By kind") { KindBreakdown(kinds: stats.byKind) }
            }
            if !stats.topTitles.isEmpty {
                PanelSection(title: "Most time with") { TopTitles(titles: Array(stats.topTitles.prefix(5))) }
            }
            if let run = stats.longestRun, run.days > 1 {
                PanelSection(title: "Longest run") {
                    Text("\(run.days) days in a row")
                        .font(.body.weight(.medium))
                    Text("\(RecapDeck.dayLabel(run.start)) – \(RecapDeck.dayLabel(run.end))")
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                }
            }
            if stats.ratings.mean != nil {
                PanelSection(title: "Ratings") { RatingsHistogram(ratings: stats.ratings) }
            }
        }
        // Recap motion rules: numbers and bars appear, they do not grow.
        .transaction { $0.animation = nil }
    }
}

extension Components.Schemas.StatsTotals {
    var finished: Int {
        moviesFinished + showsFinished + animeFinished + booksFinished + albumsFinished
    }

    var isZero: Bool {
        episodesWatched == 0 && minutesWatched == 0 && finished == 0 && activeDays == 0
    }
}

/// "45m", "2.5", "12": hours to one decimal under ten, whole above; minutes under one hour.
func hoursValue(minutes: Int) -> String {
    let hours = Double(minutes) / 60
    return hours < 10
        ? hours.formatted(.number.precision(.fractionLength(0 ... 1)))
        : Int(hours.rounded()).formatted()
}

struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.aaruDisplay(.title3, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

private struct TotalsGrid: View {
    let totals: Components.Schemas.StatsTotals
    /// GAM-006d: the window before a rolling span, for each tile's change.
    let prior: Components.Schemas.StatsTotals?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            StatTile(
                value: hoursValue(minutes: totals.minutesWatched), caption: "hours",
                delta: prior.flatMap { hoursDelta(totals.minutesWatched, $0.minutesWatched) }
            )
            StatTile(
                value: totals.episodesWatched.formatted(), caption: "episodes",
                delta: prior.flatMap { countDelta(totals.episodesWatched, $0.episodesWatched) }
            )
            StatTile(
                value: totals.finished.formatted(), caption: "finished",
                delta: prior.flatMap { countDelta(totals.finished, $0.finished) }
            )
            StatTile(
                value: totals.activeDays.formatted(),
                caption: totals.activeDays == 1 ? "active day" : "active days",
                delta: prior.flatMap { countDelta(totals.activeDays, $0.activeDays) }
            )
        }
    }

    private func countDelta(_ now: Int, _ before: Int) -> StatTile.Delta? {
        StatTile.Delta.count(now, before)
    }

    private func hoursDelta(_ now: Int, _ before: Int) -> StatTile.Delta? {
        StatTile.Delta.hours(now, before)
    }
}

struct StatTile: View {
    /// An absolute change against the window before: "+3", "−2". Never a percentage.
    struct Delta {
        var text: String
        var isUp: Bool

        static func count(_ now: Int, _ before: Int) -> Delta? {
            now == before ? nil : Delta(
                text: (now - before).formatted(.number.sign(strategy: .always())),
                isUp: now > before
            )
        }

        /// Hours round, so a change that rounds to nothing says nothing.
        static func hours(_ now: Int, _ before: Int) -> Delta? {
            guard hoursValue(minutes: now) != hoursValue(minutes: before) else { return nil }
            let sign = now > before ? "+" : "−"
            return Delta(text: sign + hoursValue(minutes: abs(now - before)), isUp: now > before)
        }
    }

    let value: String
    let caption: String
    var delta: Delta?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.aaruDisplay(.title, weight: .semibold))
                    .monospacedDigit()
                if let delta {
                    Label(delta.text, systemImage: delta.isUp ? "arrow.up.right" : "arrow.down.right")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(delta.isUp ? AnyShapeStyle(Color(.accent)) : AnyShapeStyle(Color(.muted)))
                        .accessibilityLabel("\(delta.text) from the period before")
                }
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Color(.muted))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.surface), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// Hours per bucket: days of a month or rolling window, months of a year, or years of all time.
/// A rolling window keeps a thin track under empty days, so the week still reads as seven.
private struct ActivityChart: View {
    let stats: Stats

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
            .foregroundStyle(empty ? Color(.muted).opacity(0.3) : Color(.accent))
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
        .frame(height: 180)
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

private struct KindBreakdown: View {
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

private struct TopTitles: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            .frame(height: 140)
            if let highest = ratings.highest, let rating = ratings.highestRating {
                Text("Highest: \(highest.title), \(RecapDeck.ratingLabel(rating))")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
        }
    }
}

extension MediaKind {
    init(_ kind: Components.Schemas.StatsKind.KindPayload) {
        switch kind {
        case .movie: self = .film
        case .show: self = .show
        case .anime: self = .anime
        case .book: self = .book
        case .album: self = .music
        }
    }
}
