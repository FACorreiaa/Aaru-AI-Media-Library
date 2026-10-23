import AaruCore
import Foundation

/// Tonight (AG-005): one to three things to start tonight, from the user's own library only. The
/// ranking is a fixed score, so the same library gives the same strip; reasons are templates, so
/// no model is ever called and Home works with the agent off.
struct TonightService: Sendable {
    static let maxPicks = 3
    /// How long "not for me" weighs against an item.
    static let rejectionWindow: TimeInterval = 14 * 24 * 60 * 60
    static let rejectionPenalty = 2.0

    let stores: Stores
    var now: @Sendable () -> Date = { Date() }

    func tonight(userID: UserID, timeZone identifier: String?) async throws -> Tonight {
        let zone = try Self.zone(identifier)
        let now = now()
        let day = LocalDay(now, in: zone)
        let (start, end) = Self.bounds(of: now, in: zone)
        async let continuing = stores.schedule.continueWatching(userID: userID, now: now, limit: 50)
        async let airing = stores.schedule.calendar(userID: userID, from: start, until: end, now: now)
        async let starting = stores.schedule.startWatching(userID: userID, limit: 50)
        async let reading = stores.tonight.reading(userID: userID, limit: 20)
        async let feedback = stores.tonight.feedback(
            userID: userID,
            since: now.addingTimeInterval(-Self.rejectionWindow)
        )
        var library = try await Library(
            continuing: continuing, airing: airing, starting: starting, reading: reading
        )
        library.dates = try await stores.tonight.itemDates(library.itemIDs, userID: userID)
        let picks = try await Self.rank(library, feedback: feedback, day: day, now: now, zone: zone)
        if try await stores.tonight.recordPicks(picks.map(\.libraryItemID), day: day, userID: userID, servedAt: now) {
            ProductEvents.capture(.tonightShown, userID: userID)
        }
        return Tonight(day: day, picks: picks)
    }

    func feedback(itemID: LibraryItemID, verdict: TonightVerdict, userID: UserID, timeZone: String?) async throws {
        let zone = try Self.zone(timeZone)
        let now = now()
        let saved = try await stores.tonight.saveFeedback(
            TonightFeedback(libraryItemID: itemID, verdict: verdict, day: LocalDay(now, in: zone), createdAt: now),
            userID: userID
        )
        guard saved != nil else { throw AppError.notFound("No such library item.") }
        ProductEvents.capture(.tonightRejected, userID: userID, ["verdict": verdict.rawValue])
    }

    // MARK: Ranking

    /// What Tonight ranks: the rows Home already reads, plus books in progress.
    struct Library: Sendable {
        var continuing: [ContinueEntry]
        var airing: [CalendarEntry]
        var starting: [StartEntry]
        var reading: [ReadingEntry]
        var dates: [LibraryItemID: ItemDates] = [:]

        var itemIDs: [LibraryItemID] {
            continuing.map(\.libraryItemID) + starting.map(\.libraryItemID)
        }
    }

    /// The score, highest first:
    /// - a show in progress: 3, plus momentum, plus 1.5 when three or fewer episodes are left and
    ///   0.5 when the next one ends its season;
    /// - an episode airing today of a show not already in Continue watching: 3.5;
    /// - a book in progress: 2.5, plus momentum, plus 1.5 when 80% read or 50 pages or fewer left;
    /// - a wishlist film: 1.5, plus up to 1.5 for time on the list (one point a month);
    /// - minus 2 for each "not for me" in the last 14 days. "Not tonight" hides an item until the
    ///   local day ends.
    /// Momentum is 2 when the item changed in the last two days, 1 in the last week.
    static func rank(
        _ library: Library,
        feedback: [TonightFeedback],
        day: LocalDay,
        now: Date,
        zone: TimeZone
    ) -> [TonightPick] {
        let hidden = Set(feedback.filter { $0.verdict == .notTonight && $0.day == day }.map(\.libraryItemID))
        var rejections: [LibraryItemID: Int] = [:]
        for answer in feedback where answer.verdict == .rejected {
            rejections[answer.libraryItemID, default: 0] += 1
        }
        func momentum(_ lastChange: Date?) -> Double {
            guard let lastChange else { return 0 }
            let days = now.timeIntervalSince(lastChange) / 86400
            return days <= 2 ? 2 : days <= 7 ? 1 : 0
        }

        var scored: [(pick: TonightPick, score: Double)] = []
        let continuing = Set(library.continuing.map(\.libraryItemID))
        for entry in library.continuing {
            let score = 3 + momentum(library.dates[entry.libraryItemID]?.lastChange)
                + (entry.remainingCount <= 3 ? 1.5 : 0) + (entry.isFinale ? 0.5 : 0)
            scored.append((continuePick(entry), score))
        }
        // An airing of a show the user is behind on waits: its Continue watching pick comes first.
        for entry in library.airing where !entry.watched && !continuing.contains(entry.libraryItemID) {
            scored.append((airingPick(entry, zone: zone), 3.5))
        }
        for entry in library.reading {
            let left = entry.pageCount.flatMap { count in entry.bookPage.map { max(count - $0, 0) } }
            let fraction = entry.bookPercent.map { $0 / 100 }
                ?? entry.pageCount.flatMap { count in entry.bookPage.map { Double($0) / Double(max(count, 1)) } }
            let near = (fraction ?? 0) >= 0.8 || (left.map { $0 <= 50 } ?? false)
            scored.append((readingPick(entry, pagesLeft: left), 2.5 + momentum(entry.lastChange) + (near ? 1.5 : 0)))
        }
        for entry in library.starting where entry.title.type == .movie {
            let days = library.dates[entry.libraryItemID].map { Self.days(from: $0.addedAt, to: now) }
            let score = 1.5 + min(Double(days ?? 0) / 30, 1.5)
            scored.append((startPick(entry, daysOnList: days), score))
        }

        var ranked: [(pick: TonightPick, score: Double)] = []
        for (pick, score) in scored where !hidden.contains(pick.libraryItemID) {
            let penalty = Double(rejections[pick.libraryItemID] ?? 0) * rejectionPenalty
            ranked.append((pick, score - penalty))
        }
        ranked.sort { lhs, rhs in
            guard lhs.score == rhs.score else { return lhs.score > rhs.score }
            return lhs.pick.libraryItemID.description < rhs.pick.libraryItemID.description
        }
        var seen = Set<LibraryItemID>()
        var picks: [TonightPick] = []
        for entry in ranked where picks.count < maxPicks && seen.insert(entry.pick.libraryItemID).inserted {
            picks.append(entry.pick)
        }
        return picks
    }

    // MARK: Reasons

    private static func continuePick(_ entry: ContinueEntry) -> TonightPick {
        let reason = [
            entry.nextRuntimeMinutes.map(duration),
            entry.remainingCount > 1 ? "\(entry.remainingCount) left" : "Last one aired",
            entry.isFinale ? "Season finale" : nil,
        ]
        return TonightPick(
            libraryItemID: entry.libraryItemID, title: entry.title, kind: .continue, episode: entry.next,
            episodeName: entry.nextName, minutes: entry.nextRuntimeMinutes, reason: joined(reason)
        )
    }

    private static func airingPick(_ entry: CalendarEntry, zone: TimeZone) -> TonightPick {
        let reason = [
            entry.airTimeKnown ? "Airs \(clock(entry.airsAt, zone: zone))" : "Airs today",
            entry.runtimeMinutes.map(duration),
            entry.kind == .premiere ? "Premiere" : entry.kind == .finale ? "Finale" : nil,
        ]
        return TonightPick(
            libraryItemID: entry.libraryItemID, title: entry.title, kind: .airing, episode: entry.key,
            episodeName: entry.episodeName, minutes: entry.runtimeMinutes, airsAt: entry.airsAt,
            airTimeKnown: entry.airTimeKnown, reason: joined(reason)
        )
    }

    private static func readingPick(_ entry: ReadingEntry, pagesLeft: Int?) -> TonightPick {
        let reason = if let pagesLeft {
            pagesLeft == 1 ? "1 page left" : "\(pagesLeft) pages left"
        } else if let percent = entry.bookPercent {
            "\(Int(percent.rounded()))% read"
        } else {
            "Reading"
        }
        return TonightPick(libraryItemID: entry.libraryItemID, title: entry.title, kind: .reading, reason: reason)
    }

    private static func startPick(_ entry: StartEntry, daysOnList: Int?) -> TonightPick {
        let listed: String? = daysOnList.map {
            $0 == 0 ? "Added today" : $0 == 1 ? "On your list 1 day" : "On your list \($0) days"
        }
        return TonightPick(
            libraryItemID: entry.libraryItemID, title: entry.title, kind: .start, minutes: entry.runtimeMinutes,
            reason: joined([entry.runtimeMinutes.map(duration), listed])
        )
    }

    /// "52 min", "2 h 04".
    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    private static func clock(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func joined(_ parts: [String?]) -> String {
        parts.compactMap(\.self).joined(separator: " · ")
    }

    private static func days(from start: Date, to end: Date) -> Int {
        max(Int(end.timeIntervalSince(start) / 86400), 0)
    }

    // MARK: Days

    /// The local day `now` falls on, as a UTC range.
    static func bounds(of now: Date, in zone: TimeZone) -> (Date, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = calendar.startOfDay(for: now)
        return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400))
    }

    private static func zone(_ identifier: String?) throws -> TimeZone {
        guard let zone = TimeZone(identifier: identifier ?? "UTC") else {
            let message = "Use an IANA time zone such as Europe/Lisbon."
            throw AppError(
                status: .unprocessableContent, code: "validation_failed", message: message, details: ["tz": message]
            )
        }
        return zone
    }
}
