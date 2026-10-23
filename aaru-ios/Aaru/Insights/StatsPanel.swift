import AaruAPI
import Charts
import SwiftUI

/// `StatsPanel`: one period's numbers. Totals, time per day/month/year, what kinds, top titles,
/// the longest run and how the user rated. Static on purpose: like the Recap, no number animates.
struct StatsPanel: View {
    let stats: Stats

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.section) {
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
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
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
    /// Tiles widen with the text, so larger sizes get fewer, whole tiles a row.
    @ScaledMetric(relativeTo: .title) private var tileMinimum = 140

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileMinimum), spacing: 12)], spacing: 12) {
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
        .panel()
        .accessibilityElement(children: .combine)
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
