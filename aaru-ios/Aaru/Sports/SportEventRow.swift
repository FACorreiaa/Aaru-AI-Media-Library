import SwiftUI

/// A league, team or player badge from the provider, else the sport's symbol. Decorative: the
/// row it sits in names it.
struct SportBadge: View {
    let url: String?
    var sport: String?
    var size: CGFloat = 28

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: Self.symbol(for: sport))
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(Color(.muted))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The provider's sport names, as SF Symbols.
    static func symbol(for sport: String?) -> String {
        switch sport?.lowercased() {
        case "soccer": "soccerball"
        case "basketball": "basketball"
        case "american football": "football"
        case "baseball": "baseball"
        case "ice hockey": "hockey.puck"
        case "fighting": "figure.boxing"
        case "wrestling": "figure.wrestling"
        case "tennis": "tennis.racket"
        case "motorsport": "flag.checkered"
        default: "sportscourt"
        }
    }
}

/// The live mark: a small accent dot. Still under Reduce Motion, and still otherwise too: the
/// clock beside it is the news.
struct LiveDot: View {
    var body: some View {
        Circle()
            .fill(Color(.accent))
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}

/// One event as a score line: the status column (the live clock, the kick-off or the result),
/// then home and away with badges and scores, or a card's poster and name. A favorite carries
/// the amber edge and a star (gold is edge light only, never text). VoiceOver reads it as one
/// sentence and opens it as a button.
struct SportEventRow: View {
    let event: SportEvent
    /// Favorites show the day too ("Tomorrow" over "20:45"); Schedule's day is the strip's.
    var showsDay = false
    let onOpen: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var statusWidth: CGFloat = 64

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                statusColumn
                    .frame(width: statusWidth, alignment: .leading)
                if event.isCard {
                    CardLine(event: event)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        SideLine(side: event.home, winner: winner == .home, showsScore: showsScore)
                        SideLine(side: event.away, winner: winner == .away, showsScore: showsScore)
                    }
                }
                if event.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(.gold))
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .overlay(alignment: .leading) {
                if event.isFavorite {
                    Capsule()
                        .fill(Color(.gold))
                        .frame(width: 3)
                        .padding(.vertical, 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the score and where to watch")
    }

    private var showsScore: Bool {
        event.status == .live || event.status == .finished
    }

    private enum Side { case home, away }

    private var winner: Side? {
        guard event.status == .finished, let home = event.home?.score, let away = event.away?.score,
              home != away
        else { return nil }
        return home > away ? .home : .away
    }

    private var statusColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            if event.status == .live {
                HStack(spacing: 4) {
                    LiveDot()
                    Text(SportLabels.clock(event.progress))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.accent))
                }
            } else {
                if showsDay {
                    Text(SportLabels.dayLabel(event.startsAt, day: event.day))
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(event.statusText)
                    .font(.footnote.weight(event.status == .scheduled ? .semibold : .regular))
                    .foregroundStyle(Color(event.status == .scheduled ? .ink : .muted))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .monospacedDigit()
    }
}

/// Home or away: badge, name, and the score when there is one.
private struct SideLine: View {
    let side: SportSide?
    let winner: Bool
    let showsScore: Bool

    var body: some View {
        HStack(spacing: 8) {
            SportBadge(url: side?.badgeUrl, size: 20)
            Text(side?.name ?? "TBD")
                .font(.subheadline.weight(winner ? .semibold : .regular))
                .foregroundStyle(Color(.ink))
                .lineLimit(1)
            Spacer(minLength: 8)
            if showsScore, let score = side?.score {
                Text("\(score)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.ink))
                    .monospacedDigit()
            }
        }
    }
}

/// A UFC or WWE card: its poster and name, and the venue.
private struct CardLine: View {
    let event: SportEvent

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: event.imageUrl.flatMap(URL.init(string:))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Color(.stone)
                }
            }
            .frame(width: 56, height: 36)
            .clipShape(.rect(cornerRadius: AaruRadius.thumb, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.ink))
                    .lineLimit(2)
                if let venue = event.venue {
                    Text(venue)
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The provider's credit, at the foot of every Sports view.
struct SportsCredit: View {
    var body: some View {
        Text("Data: TheSportsDB")
            .font(.caption)
            .foregroundStyle(Color(.muted))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
