import Foundation

/// Tonight on the Field (VIEWS.md `TonightStrip`, pulled forward 2026-10-21): one thing to watch
/// now and at most one more, composed on the device from rows Home already has: Continue
/// watching (every next episode there has aired) and today's airings. It ranks nothing new and
/// writes nothing; the agent-composed Tonight, with "not tonight", stays in M13. The web's
/// `lib/home/tonight.ts` follows the same rule.
enum TonightPick {
    case continuing(ContinueEntry)
    case airing(CalendarEntry)

    var libraryItemId: String {
        switch self {
        case let .continuing(entry): entry.libraryItemId
        case let .airing(entry): entry.libraryItemId
        }
    }

    var title: TitleSummary {
        switch self {
        case let .continuing(entry): entry.title
        case let .airing(entry): entry.title
        }
    }

    /// "S4 · E3 · Name".
    var episodeLine: String {
        switch self {
        case let .continuing(entry):
            [EpisodeCode.short(season: entry.next.season, number: entry.next.number), entry.nextName].compactMap(\.self)
                .joined(separator: " · ")
        case let .airing(entry):
            [entry.shortCode, entry.episodeName].compactMap(\.self).joined(separator: " · ")
        }
    }

    /// Why it is here: "47m · 3 left · Season finale", or "Airs 9:00 PM · 44m · Premiere".
    var reason: String {
        switch self {
        case let .continuing(entry):
            return [
                entry.nextRuntimeMinutes.flatMap { $0 > 0 ? durationLabel(minutes: $0) : nil },
                entry.remainingCount > 1 ? "\(entry.remainingCount) left" : "Last one aired",
                entry.isFinale ? "Season finale" : nil,
            ].compactMap(\.self).joined(separator: " · ")
        case let .airing(entry):
            return [
                entry.timeText.map { "Airs \($0)" } ?? "Airs today",
                entry.runtimeMinutes.flatMap { $0 > 0 ? durationLabel(minutes: $0) : nil },
                entry.badge?.label,
            ].compactMap(\.self).joined(separator: " · ")
        }
    }
}

struct Tonight {
    let primary: TonightPick
    let also: TonightPick?

    /// The show at the top of Continue watching, else the first airing today; then one more
    /// from the other source, never the same show twice. What is playing now is never in it:
    /// Now playing already shows it. Nil when there is nothing.
    static func compose(
        continuing: [ContinueEntry], today: [CalendarEntry], playing: Set<String> = []
    ) -> Tonight? {
        let continuing = continuing.filter { !playing.contains($0.libraryItemId) }
        let today = today.filter { !playing.contains($0.libraryItemId) }
        let candidates: [TonightPick] = continuing.prefix(1).map(TonightPick.continuing)
            + today.map(TonightPick.airing)
            + continuing.dropFirst().map(TonightPick.continuing)
        guard let primary = candidates.first else { return nil }
        let also = candidates.dropFirst().first { $0.libraryItemId != primary.libraryItemId }
        return Tonight(primary: primary, also: also)
    }
}

extension HomeModel {
    /// Unwatched episodes of the user's shows that air today, in air order.
    var airingToday: [CalendarEntry] {
        let today = CalendarDay(calendar.dateComponents([.year, .month, .day], from: now()))
        return upcoming.filter { $0.day(in: calendar) == today }
    }

    var tonight: Tonight? {
        Tonight.compose(continuing: continueWatching, today: airingToday, playing: playingItemIds)
    }

    /// The Field's line under its heading: "Tuesday evening · 3 in progress · 2 airing today".
    var fieldLine: String {
        let inProgress = counts?.inProgress ?? 0
        let airing = airingToday.count
        let parts: [String?] = [
            Daypart(hour: calendar.component(.hour, from: now())).heading(on: now()),
            inProgress > 0 ? "\(inProgress) in progress" : nil,
            airing > 0 ? "\(airing) airing today" : nil,
        ]
        return parts.compactMap(\.self).joined(separator: " · ")
    }
}
