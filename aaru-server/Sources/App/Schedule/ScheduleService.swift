import AaruCore
import Foundation

/// Calendar (CAL-001) and Up Next (UPN-001, UPN-002). Both are derived reads over the library;
/// neither has a table of its own. Neither calls a provider (CAL-004): episodes are loaded by
/// `CatalogRefresher`, and the calendar reports how many shows it is still waiting on.
struct ScheduleService: Sendable {
    /// Six weeks: a month view's full grid, Monday before the 1st to Sunday after the last.
    static let maxCalendarSpan: TimeInterval = 42 * 24 * 60 * 60
    /// An in-progress item untouched this long is unfinished business (UPN-002).
    static let stalledAfter: TimeInterval = 30 * 24 * 60 * 60
    static let unfinishedLimit = 20

    let stores: Stores
    var now: @Sendable () -> Date = { Date() }

    func calendar(userID: UserID, from: Date, until: Date) async throws -> [CalendarEntry] {
        guard until > from, until.timeIntervalSince(from) <= Self.maxCalendarSpan else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "The range must be positive and at most 42 days.",
                details: ["to": "The range must be positive and at most 42 days."]
            )
        }
        return try await stores.schedule.calendar(userID: userID, from: from, until: until, now: now())
    }

    /// Tracked shows whose episodes the refresher has not tried yet: the calendar may still grow.
    func pendingShows(userID: UserID) async throws -> Int {
        try await stores.schedule.pendingShowCount(userID: userID)
    }

    func upNext(userID: UserID) async throws -> UpNext {
        let now = now()
        async let continuing = stores.schedule.continueWatching(userID: userID, now: now, limit: 50)
        async let starting = stores.schedule.startWatching(userID: userID, limit: 20)
        async let counts = stores.schedule.libraryCounts(userID: userID)
        async let unfinished = stores.schedule.unfinished(
            userID: userID, stalledBefore: now.addingTimeInterval(-Self.stalledAfter), now: now,
            limit: Self.unfinishedLimit
        )
        return try await UpNext(
            continueWatching: continuing, startWatching: starting, counts: counts, unfinished: unfinished
        )
    }
}
