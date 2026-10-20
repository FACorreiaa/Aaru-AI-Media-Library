import AaruAPI
import Charts
import SwiftUI

/// `StatsPanel`: one period's numbers. Totals, time per day/month/year, what kinds, top titles,
/// the longest run and how the user rated. Static on purpose: like the Recap, no number animates.
struct StatsPanel: View {
    let stats: Stats

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            TotalsGrid(totals: stats.totals)
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
        moviesFinished + showsFinished + animeFinished + booksFinished
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

private struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

private struct TotalsGrid: View {
    let totals: Components.Schemas.StatsTotals

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            StatTile(value: hoursValue(minutes: totals.minutesWatched), caption: "hours")
            StatTile(value: totals.episodesWatched.formatted(), caption: "episodes")
            StatTile(value: totals.finished.formatted(), caption: "finished")
            StatTile(
                value: totals.activeDays.formatted(),
                caption: totals.activeDays == 1 ? "active day" : "active days"
            )
        }
    }
}

private struct StatTile: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .serif, weight: .semibold))
                .monospacedDigit()
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

/// Hours per bucket: days of a month, months of a year, or years of all time.
private struct ActivityChart: View {
    let stats: Stats

    var body: some View {
        Chart(stats.buckets, id: \.start) { bucket in
            BarMark(
                x: .value("Period", bucket.start),
                y: .value("Hours", Double(bucket.minutes) / 60)
            )
            .foregroundStyle(Color.accentColor)
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

    /// Every bucket for months and years; every fifth day in a month so labels do not collide.
    private var axisValues: [String] {
        let starts = stats.buckets.map(\.start)
        guard stats.span == .month else { return starts }
        return starts.enumerated().filter { $0.offset % 5 == 0 }.map(\.element)
    }

    private func label(_ start: String, full: Bool) -> String {
        let parts = start.split(separator: "-").compactMap { Int($0) }
        switch stats.span {
        case .month:
            return full ? RecapDeck.dayLabel(start) : "\(parts.count > 2 ? parts[2] : 1)"
        case .year:
            let name = RecapDeck.months[max(0, min(11, (parts.count > 1 ? parts[1] : 1) - 1))]
            return full ? name : String(name.prefix(1))
        case .all:
            return "\(parts.first ?? stats.year)"
        }
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
                        .font(.system(.title3, design: .serif, weight: .semibold))
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
private struct RatingsHistogram: View {
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
                .foregroundStyle(Color.weekGold)
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
        }
    }
}
