import SwiftUI

/// GAM-006a: one card of the Recap story per `RecapCard` case. Each element rises in once, on a
/// stagger; numbers count up. With Reduce Motion everything is simply there.
struct RecapCardView: View {
    let card: RecapCard
    let stats: Stats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch card {
            case let .intro(heading, partial):
                Eyebrow(text: partial ? "So far" : "Your recap")
                Text(heading)
                    .font(.system(size: 56, weight: .medium, design: .serif))
                    .lineSpacing(-4)
                    .padding(.top, 16)
                    .rise(0.12)
                Line(text: "Everything you watched and read, from your own shelf. Tap to go on.")
            case let .time(minutes, caption):
                Eyebrow(text: "Time with stories")
                Big { CountUp(value: minutes) }
                Text("minutes").font(.title3).padding(.top, 4).rise(0.2)
                Line(text: caption)
            case let .episodes(count, bars, busiest):
                Eyebrow(text: "Episodes")
                Big { CountUp(value: count) }
                BarChart(bars: bars).padding(.top, 32)
                if let busiest {
                    Line(text: "\(busiest) was your busiest.", delay: 0.7)
                }
            case let .top(entry):
                Eyebrow(text: "Most time with")
                PosterView(url: entry.title.posterURL, kind: entry.title.mediaKind)
                    .frame(width: 168)
                    .padding(.top, 24)
                    .pop(0.12)
                Text(entry.title.title)
                    .font(.system(size: 40, weight: .medium, design: .serif))
                    .padding(.top, 24)
                    .rise(0.32)
                Line(text: timeLine(entry), delay: 0.46)
            case let .topList(entries):
                Eyebrow(text: "Your top \(entries.count)")
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { rank, entry in
                        TopRow(entry: entry, rank: rank + 1).rise(0.15 + Double(rank) * 0.11)
                    }
                }
                .padding(.top, 24)
            case let .finished(parts):
                Eyebrow(text: "Finished")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { offset, part in
                        Text(RecapDeck.countLabel(part.kind, part.count))
                            .font(.system(size: 48, weight: .medium, design: .serif))
                            .monospacedDigit()
                            .rise(0.12 + Double(offset) * 0.14)
                    }
                }
                .padding(.top, 16)
            case let .run(days, range):
                Eyebrow(text: "Longest run")
                Big { CountUp(value: days) }
                Text("days in a row").font(.title3).padding(.top, 4).rise(0.2)
                Line(text: range)
            case let .ratings(mean, count, highest, highestRating):
                Eyebrow(text: "Your average rating")
                Big { Text(RecapDeck.ratingLabel(mean)) }
                Line(text: "Across \(count) finished \(count == 1 ? "title" : "titles").", delay: 0.24)
                if let highest {
                    HStack(spacing: 16) {
                        PosterView(url: highest.posterURL, kind: highest.mediaKind).frame(width: 56)
                        VStack(alignment: .leading) {
                            Text("Rated highest").font(.subheadline).opacity(0.75)
                            HStack(alignment: .firstTextBaseline) {
                                Text(highest.title).font(.system(.title2, design: .serif))
                                if let highestRating {
                                    Text(RecapDeck.ratingLabel(highestRating)).monospacedDigit().opacity(0.8)
                                }
                            }
                        }
                    }
                    .padding(.top, 32)
                    .rise(0.48)
                }
            case let .bookends(first, last):
                Eyebrow(text: "Bookends")
                VStack(alignment: .leading, spacing: 32) {
                    Moment(label: "First", moment: first).rise(0.12)
                    Moment(label: "Last", moment: last).rise(0.34)
                }
                .padding(.top, 24)
            case .summary:
                Eyebrow(text: RecapPeriod(year: stats.year, month: stats.month).label)
                Text("That was your \(stats.month == nil ? "year" : "month") in Aaru.")
                    .font(.system(size: 40, weight: .medium, design: .serif))
                    .padding(.top, 16)
                    .rise(0.12)
                RecapShareButton(stats: stats).padding(.top, 40).rise(0.32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeLine(_ entry: StatsTitle) -> String {
        entry.episodes > 0
            ? "\(entry.episodes) episodes, \(entry.minutes.formatted()) minutes."
            : "\(entry.minutes.formatted()) minutes."
    }
}

private struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.subheadline.weight(.medium))
            .tracking(1.8)
            .opacity(0.8)
            .rise(0)
    }
}

private struct Big<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.system(size: 88, weight: .medium, design: .serif))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(.top, 12)
            .rise(0.12)
    }
}

private struct Line: View {
    let text: String
    var delay = 0.36

    var body: some View {
        Text(text)
            .font(.title3)
            .opacity(0.9)
            .frame(maxWidth: 380, alignment: .leading)
            .padding(.top, 20)
            .rise(delay)
    }
}

private struct TopRow: View {
    let entry: StatsTitle
    let rank: Int

    var body: some View {
        HStack(spacing: 16) {
            Text("\(rank)")
                .font(.system(.title2, design: .serif))
                .monospacedDigit()
                .opacity(0.7)
                .frame(width: 24, alignment: .leading)
            PosterView(url: entry.title.posterURL, kind: entry.title.mediaKind).frame(width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.title).font(.system(.title3, design: .serif)).lineLimit(1)
                Text(entry.episodes > 0 ? "\(entry.episodes) episodes" : "\(entry.minutes) minutes")
                    .font(.subheadline)
                    .opacity(0.75)
            }
        }
    }
}

private struct Moment: View {
    let label: String
    let moment: StatsMoment

    var body: some View {
        HStack(spacing: 16) {
            PosterView(url: moment.title.posterURL, kind: moment.title.mediaKind).frame(width: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(label) · \(moment.at.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.subheadline)
                    .opacity(0.75)
                Text(moment.title.title).font(.system(size: 28, design: .serif))
            }
        }
    }
}

/// One bar per month or day; the busiest is solid, the rest translucent. Bars grow from the
/// baseline in sequence.
private struct BarChart: View {
    let bars: [RecapCard.Bar]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { offset, bar in
                VStack(spacing: 4) {
                    GeometryReader { proxy in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .opacity(bar.busiest ? 1 : 0.35)
                                .frame(height: max(bar.height > 0 ? 4 : 1, proxy.size.height * bar.height))
                                .scaleEffect(y: grown ? 1 : 0, anchor: .bottom)
                                .animation(
                                    reduceMotion ? nil : .spring(duration: 0.7).delay(0.2 + Double(offset) * 0.035),
                                    value: grown
                                )
                        }
                    }
                    if bars.count <= 12 {
                        Text(bar.label).font(.caption2).opacity(0.7)
                    }
                }
            }
        }
        .frame(height: 160)
        .accessibilityHidden(true)
        .onAppear { grown = true }
    }
}

/// Counts from zero to `value` once, digits rolling; the final number at once with Reduce Motion.
private struct CountUp: View {
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        Text(shown.formatted())
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear {
                guard !reduceMotion else {
                    shown = value
                    return
                }
                withAnimation(.smooth(duration: 1.2).delay(0.15)) { shown = value }
            }
            .accessibilityLabel(value.formatted())
    }
}

private struct Entrance: ViewModifier {
    let delay: Double
    let pop: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion || pop ? 0 : 12)
            .scaleEffect(shown || reduceMotion || !pop ? 1 : 0.85)
            .rotationEffect(.degrees(shown || reduceMotion || !pop ? 0 : -2))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(pop ? .spring(duration: 0.7, bounce: 0.35).delay(delay) : .smooth(duration: 0.6)
                    .delay(delay))
                {
                    shown = true
                }
            }
    }
}

private extension View {
    /// Fades and lifts in after `delay` seconds.
    func rise(_ delay: Double) -> some View {
        modifier(Entrance(delay: delay, pop: false))
    }

    /// Springs in from slightly small and tilted.
    func pop(_ delay: Double) -> some View {
        modifier(Entrance(delay: delay, pop: true))
    }
}
