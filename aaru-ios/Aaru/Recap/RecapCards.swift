import SwiftUI

/// GAM-006a/e: one card of the Recap story per `RecapCard` case. Each element rises in once, on a
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
                    .font(.aaruDisplay(size: 56))
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
                    Line(text: busiest, delay: 0.7)
                }
            case let .biggestDay(day, episodes, minutes):
                Eyebrow(text: "Your biggest day")
                Text(day)
                    .font(.aaruDisplay(size: 64))
                    .padding(.top, 16)
                    .rise(0.12)
                Line(text: dayLine(episodes: episodes, minutes: minutes))
            case let .top(entry):
                Eyebrow(text: "Most time with")
                OutlinedPoster(url: entry.title.posterURL, kind: entry.title.mediaKind)
                    .frame(width: 168)
                    // The poster's own colours, blurred behind it: a glow, not a second image.
                    .background {
                        AsyncImage(url: entry.title.posterURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.clear
                        }
                        .scaleEffect(1.25)
                        .blur(radius: 40)
                        .opacity(0.6)
                        .accessibilityHidden(true)
                    }
                    .padding(.top, 24)
                    .pop(0.12)
                Text(entry.title.title)
                    .font(.aaruDisplay(size: 40))
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
            case let .genres(genres):
                Eyebrow(text: "Your genres")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(genres.enumerated()), id: \.offset) { rank, genre in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text("\(rank + 1)")
                                .font(.aaruDisplay(.title2))
                                .monospacedDigit()
                                .opacity(0.7)
                                .frame(width: 24, alignment: .leading)
                            Text(genre.name)
                                .font(.aaruDisplay(size: 44))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                        }
                        .rise(0.12 + Double(rank) * 0.16)
                    }
                }
                .padding(.top, 16)
                if let first = genres.first {
                    Line(text: genreLine(first), delay: 0.64)
                }
            case let .kinds(parts):
                Eyebrow(text: "Where the time went")
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { offset, part in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(part.kind.label).font(.aaruDisplay(.title))
                                Spacer()
                                Text(part.share.formatted(.percent.precision(.fractionLength(0))))
                                    .font(.title3)
                                    .monospacedDigit()
                                    .opacity(0.8)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.primary.opacity(0.2))
                                    Capsule().fill(.primary)
                                        .frame(width: max(4, proxy.size.width * part.share))
                                }
                            }
                            .frame(height: 8)
                            .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                        .rise(0.12 + Double(offset) * 0.14)
                    }
                }
                .padding(.top, 24)
            case let .finished(parts):
                Eyebrow(text: "Finished")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { offset, part in
                        Text(RecapDeck.countLabel(part.kind, part.count))
                            .font(.aaruDisplay(size: 48))
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
                        OutlinedPoster(url: highest.posterURL, kind: highest.mediaKind).frame(width: 56)
                        VStack(alignment: .leading) {
                            Text("Rated highest").font(.subheadline).opacity(0.75)
                            HStack(alignment: .firstTextBaseline) {
                                Text(highest.title).font(.aaruDisplay(.title2))
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
            case let .persona(title, line):
                Eyebrow(text: "Your \(String(stats.year)), in a word")
                Text(title)
                    .font(.aaruDisplay(size: 56))
                    .padding(.top, 16)
                    .pop(0.16)
                Line(text: line, delay: 0.48)
            case .summary:
                Eyebrow(text: RecapPeriod(year: stats.year, month: stats.month).label)
                Text(stats.isPartial
                    ? "That's your \(stats.month == nil ? "year" : "month") in Aaru so far."
                    : "That was your \(stats.month == nil ? "year" : "month") in Aaru.")
                    .font(.aaruDisplay(size: 40))
                    .padding(.top, 16)
                    .rise(0.12)
                RecapShareButton(stats: stats).padding(.top, 40).rise(0.32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayLine(episodes: Int, minutes: Int) -> String {
        let parts = [
            episodes > 0 ? "\(episodes) \(episodes == 1 ? "episode" : "episodes")" : nil,
            minutes > 0 ? "\(hoursValue(minutes: minutes)) hours" : nil,
        ].compactMap(\.self)
        return parts.joined(separator: ", ") + " in one day."
    }

    private func genreLine(_ genre: StatsGenre) -> String {
        "\(hoursValue(minutes: genre.minutes)) hours of \(genre.name.lowercased()), across \(genre.titles) "
            + (genre.titles == 1 ? "title." : "titles.")
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
            .font(.aaruDisplay(size: 88))
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
                .font(.aaruDisplay(.title2))
                .monospacedDigit()
                .opacity(0.7)
                .frame(width: 24, alignment: .leading)
            OutlinedPoster(url: entry.title.posterURL, kind: entry.title.mediaKind).frame(width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.title).font(.aaruDisplay(.title3)).lineLimit(1)
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
            OutlinedPoster(url: moment.title.posterURL, kind: moment.title.mediaKind).frame(width: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(label) · \(moment.at.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.subheadline)
                    .opacity(0.75)
                Text(moment.title.title).font(.aaruDisplay(size: 28))
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

/// A poster with a hairline in the card's ink: the placeholder is Surface, which is also one of
/// the story's backdrops.
private struct OutlinedPoster: View {
    let url: URL?
    let kind: MediaKind

    var body: some View {
        PosterView(url: url, kind: kind)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.2), lineWidth: 1))
    }
}
