import SwiftUI

/// One episode as a row (CAL-003): poster, show, code and name, network and time or an air date,
/// the badge, and a 44 pt tick. The row opens the episode sheet; the tick works on its own. The
/// month agenda, the iPhone day sheet and Missed use it.
struct CalendarEpisodeRow: View {
    let entry: CalendarEntry
    let feed: CalendarFeed
    /// Replaces "network · time", e.g. "Aired Mon 13 Oct" in Missed.
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Button { feed.open(entry) } label: {
                HStack(spacing: 12) {
                    PosterView(
                        url: entry.title.posterUrl.flatMap(URL.init(string:)),
                        kind: entry.title.isAnime ? .anime : .show
                    )
                    .frame(width: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(entry.title.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(.ink))
                                .lineLimit(1)
                            if let badge = entry.badge {
                                WeekBadge(badge: badge)
                            }
                        }
                        Text([entry.shortCode, entry.episodeName].compactMap(\.self).joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(Color(.ink))
                            .lineLimit(1)
                        if let line = detail ?? entry.whereAndWhen {
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(Color(.muted))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the episode")
            CalendarTick(entry: entry, feed: feed)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .opacity(entry.watched ? 0.55 : 1)
    }
}

/// The round watched toggle with a 44 pt target, disabled while its write is pending.
struct CalendarTick: View {
    let entry: CalendarEntry
    let feed: CalendarFeed

    var body: some View {
        Button {
            Task { await feed.toggle(entry) }
        } label: {
            Image(systemName: entry.watched ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(entry.watched ? Color(.accent) : Color(.ink).opacity(0.35))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(feed.pending.contains(entry.cellID))
        .sensoryFeedback(.success, trigger: entry.watched) { _, now in now }
        .accessibilityLabel("\(entry.watched ? "Mark unwatched" : "Mark watched"): \(entry.title.title) \(entry.shortCode)")
    }
}
