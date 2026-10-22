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
                RecapLine(text: "Everything you watched, read and listened to, from your own library. Tap to go on.")
            case let .time(minutes, caption):
                Eyebrow(text: "Time with stories")
                RecapBig { RecapCountUp(value: minutes) }
                Text("minutes").font(.title3).padding(.top, 4).rise(0.2)
                RecapLine(text: caption)
            case let .episodes(count, bars, busiest):
                Eyebrow(text: "Episodes")
                RecapBig { RecapCountUp(value: count) }
                RecapBarChart(bars: bars).padding(.top, 32)
                if let busiest {
                    RecapLine(text: busiest, delay: 0.7)
                }
            case let .biggestDay(day, episodes, minutes):
                Eyebrow(text: "Your biggest day")
                Text(day)
                    .font(.aaruDisplay(size: 64))
                    .padding(.top, 16)
                    .rise(0.12)
                RecapLine(text: dayLine(episodes: episodes, minutes: minutes))
            case let .top(entry):
                Eyebrow(text: "Most time with")
                RecapPoster(url: entry.title.posterURL, kind: entry.title.mediaKind)
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
                RecapLine(text: timeLine(entry), delay: 0.46)
            case let .topList(entries):
                Eyebrow(text: "Your top \(entries.count)")
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { rank, entry in
                        RecapTopRow(entry: entry, rank: rank + 1).rise(0.15 + Double(rank) * 0.11)
                    }
                }
                .padding(.top, 24)
            case let .onRepeat(artist, plays, minutes, tracks):
                OnRepeatCard(artist: artist, plays: plays, minutes: minutes, tracks: tracks)
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
                    RecapLine(text: genreLine(first), delay: 0.64)
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
                RecapBig { RecapCountUp(value: days) }
                Text("days in a row").font(.title3).padding(.top, 4).rise(0.2)
                RecapLine(text: range)
            case let .ratings(mean, count, highest, highestRating):
                Eyebrow(text: "Your average rating")
                RecapBig { Text(RecapDeck.ratingLabel(mean)) }
                RecapLine(text: "Across \(count) finished \(count == 1 ? "title" : "titles").", delay: 0.24)
                if let highest {
                    HStack(spacing: 16) {
                        RecapPoster(url: highest.posterURL, kind: highest.mediaKind).frame(width: 56)
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
                    RecapMoment(label: "First", moment: first).rise(0.12)
                    RecapMoment(label: "Last", moment: last).rise(0.34)
                }
                .padding(.top, 24)
            case let .persona(title, line):
                Eyebrow(text: "Your \(String(stats.year)), in a word")
                Text(title)
                    .font(.aaruDisplay(size: 56))
                    .padding(.top, 16)
                    .pop(0.16)
                RecapLine(text: line, delay: 0.48)
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
