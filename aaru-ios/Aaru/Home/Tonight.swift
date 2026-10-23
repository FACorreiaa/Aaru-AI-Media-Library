import AaruAPI
import Foundation

typealias RankedPick = Components.Schemas.TonightPick

/// Tonight on the Field (VIEWS.md `TonightStrip`, AG-005): one thing to watch or read now and at
/// most one more. The server ranks it (`/v1/tonight`, with "not tonight" and "not for me");
/// without an answer for today (offline, first launch) it is composed on the device from rows
/// Home already has: Continue watching (every next episode there has aired) and today's airings.
/// The web's `lib/home/tonight.ts` follows the same rule.
enum TonightPick {
    case continuing(ContinueEntry)
    case airing(CalendarEntry)
    /// A server pick. `next` is Continue watching's card for the same show, so the tick works.
    case ranked(RankedPick, next: ContinueEntry?)

    var libraryItemId: String {
        switch self {
        case let .continuing(entry): entry.libraryItemId
        case let .airing(entry): entry.libraryItemId
        case let .ranked(pick, _): pick.libraryItemId
        }
    }

    var title: TitleSummary {
        switch self {
        case let .continuing(entry): entry.title
        case let .airing(entry): entry.title
        case let .ranked(pick, _): pick.title
        }
    }

    /// The episode the tick marks, when there is one to mark.
    var markable: ContinueEntry? {
        switch self {
        case let .continuing(entry): entry
        case .airing: nil
        case let .ranked(_, next): next
        }
    }

    /// "S4 · E3 · Name". Empty for a book or a film.
    var episodeLine: String {
        switch self {
        case let .continuing(entry):
            Self.episodeLine(entry)
        case let .airing(entry):
            [entry.shortCode, entry.episodeName].compactMap(\.self).joined(separator: " · ")
        case let .ranked(_, next?):
            Self.episodeLine(next)
        case let .ranked(pick, nil):
            [
                pick.episode.map { EpisodeCode.short(season: $0.season, number: $0.number) },
                pick.episodeName,
            ].compactMap(\.self).joined(separator: " · ")
        }
    }

    private static func episodeLine(_ entry: ContinueEntry) -> String {
        [EpisodeCode.short(season: entry.next.season, number: entry.next.number), entry.nextName].compactMap(\.self)
            .joined(separator: " · ")
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
        case let .ranked(pick, _):
            return pick.reason
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

    /// The server's picks in its order, less what is playing now; each show's pick carries its
    /// Continue watching card. Nil when none is left.
    static func ranked(
        _ picks: [RankedPick], continuing: [ContinueEntry], playing: Set<String> = []
    ) -> Tonight? {
        let candidates = picks.filter { !playing.contains($0.libraryItemId) }.map { pick in
            let next = pick.kind == ._continue ? continuing.first { $0.libraryItemId == pick.libraryItemId } : nil
            return TonightPick.ranked(pick, next: next)
        }
        guard let primary = candidates.first else { return nil }
        return Tonight(primary: primary, also: candidates.dropFirst().first)
    }
}

extension HomeModel {
    /// Unwatched episodes of the user's shows that air today, in air order.
    var airingToday: [CalendarEntry] {
        let today = CalendarDay(calendar.dateComponents([.year, .month, .day], from: now()))
        return upcoming.filter { $0.day(in: calendar) == today }
    }

    /// The server's answer for today when there is one, else the composition on the device.
    /// What the user set aside since it loaded is left out of either.
    var tonight: Tonight? {
        let hidden = playingItemIds.union(tonightFeed.hidden)
        if let ranked = tonightFeed.answer, ranked.day == todayKey {
            return Tonight.ranked(ranked.picks, continuing: continueWatching, playing: hidden)
        }
        return Tonight.compose(continuing: continueWatching, today: airingToday, playing: hidden)
    }

    /// Today as the server writes a Tonight day, "2026-10-23".
    var todayKey: String {
        let parts = calendar.dateComponents([.year, .month, .day], from: now())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
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
