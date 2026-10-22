import AaruAPI
import SwiftUI

/// `ContinueRow` card: backdrop, the next episode's runtime, "Finale", what is left, and a check
/// that marks the next episode watched.
struct ContinueCard: View {
    let entry: ContinueEntry
    let width: CGFloat
    let isPending: Bool
    let onCheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: entry.libraryItemId) {
                HomeArt(url: artURL, aspect: 16 / 9)
                    .overlay(alignment: .bottomLeading) { chips.padding(8) }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .modifier(HoverLift())
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.accent))
                        .lineLimit(1)
                    Text(episodeLine)
                        .font(.caption)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: onCheck) {
                    Image(systemName: isPending ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(Color(.accent))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isPending)
                .accessibilityLabel("Mark \(entry.title.title) \(episodeCode) watched")
            }
        }
        .frame(width: width)
        .accessibilityElement(children: .contain)
    }

    private var artURL: URL? {
        (entry.title.backdropUrl ?? entry.title.posterUrl).flatMap(URL.init(string:))
    }

    private var episodeCode: String {
        EpisodeCode.short(season: entry.next.season, number: entry.next.number)
    }

    /// "S1 · E8 · Episode name".
    private var episodeLine: String {
        [episodeCode, entry.nextName].compactMap(\.self).joined(separator: " · ")
    }

    private var chips: some View {
        HStack(spacing: 6) {
            if let runtime = entry.nextRuntimeMinutes, runtime > 0 {
                HomeChip(text: durationLabel(minutes: runtime))
            }
            if entry.isFinale {
                HomeChip(text: "Finale", tint: Color(.ink), foreground: Color(.paper))
            }
            Spacer(minLength: 0)
            HomeChip(text: leftLabel)
        }
    }

    /// "10 left · 8h 40m", or just "1 left".
    private var leftLabel: String {
        let count = "\(entry.remainingCount) left"
        return entry.remainingMinutes > 0 ? "\(count) · \(durationLabel(minutes: entry.remainingMinutes))" : count
    }
}

/// `StartRow` card: a poster and its runtime, for "what can I start tonight".
struct StartCard: View {
    let entry: StartEntry
    let width: CGFloat

    var body: some View {
        NavigationLink(value: entry.libraryItemId) {
            VStack(alignment: .leading, spacing: 6) {
                HomeArt(url: entry.title.posterURL, aspect: entry.title.mediaKind.posterAspect)
                    .overlay(alignment: .bottomLeading) {
                        if let runtime = entry.runtimeMinutes, runtime > 0 {
                            HomeChip(text: durationLabel(minutes: runtime)).padding(6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                // The name sits under the card, so a missing poster needs no text on the wash.
                Text(entry.title.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .modifier(HoverLift())
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        [entry.title.title, entry.runtimeMinutes.map { durationLabel(minutes: $0) }]
            .compactMap(\.self).joined(separator: ", ")
    }
}

/// `ListeningRow` card (MUS-001): an album being listened to. A square cover with its year as
/// the badge, the name, and the artist under it.
struct ListeningCard: View {
    let row: LibraryRow
    let width: CGFloat

    var body: some View {
        NavigationLink(value: row.id) {
            VStack(alignment: .leading, spacing: 6) {
                HomeArt(url: row.posterURL, aspect: MediaKind.music.posterAspect)
                    .overlay(alignment: .bottomLeading) {
                        if let year = row.year {
                            HomeChip(text: String(year)).padding(6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let artist = row.byline {
                        Text(artist)
                            .font(.caption2)
                            .foregroundStyle(Color(.muted))
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .modifier(HoverLift())
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        [row.title, row.byline, row.year.map(String.init)].compactMap(\.self).joined(separator: ", ")
    }
}

/// `CalendarRow` card: a small banner with when it airs ("In 3 hours", "Tomorrow").
struct AiringCard: View {
    let entry: CalendarEntry
    let when: String
    let width: CGFloat
    /// Opens the episode's sheet, as the calendar does (UX-092).
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HomeArt(
                    url: (entry.title.backdropUrl ?? entry.title.posterUrl).flatMap(URL.init(string:)),
                    aspect: 16 / 6
                )
                .overlay(alignment: .topLeading) {
                    HomeChip(
                        text: when,
                        tint: isSoon ? Color(.accent) : .black.opacity(0.55),
                        foreground: isSoon ? Color(.paper) : .white
                    )
                    .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    if let badge = entry.badge {
                        WeekBadge(badge: badge).padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(.accent))
                        .lineLimit(1)
                    Text([EpisodeCode.short(season: entry.season, number: entry.number), entry.episodeName]
                        .compactMap(\.self).joined(separator: " · "))
                        .font(.caption2)
                        .lineLimit(1)
                    if let detail = entry.whereAndWhen {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(Color(.muted))
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .modifier(HoverLift())
        .accessibilityLabel([entry.title.title, EpisodeCode.short(season: entry.season, number: entry.number), when]
            .joined(separator: ", "))
        .accessibilityHint("Shows the episode")
    }

    /// Today's and the next few hours' airings get the accent.
    private var isSoon: Bool {
        when.hasPrefix("Today") || when.hasPrefix("In ") && !when.hasSuffix("days")
    }
}
