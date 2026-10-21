import AaruCore
import Foundation

/// Calendar (CAL-001) and Up Next (UPN-001, UPN-002). Both are derived reads over the library;
/// neither has a table of its own.
struct ScheduleService: Sendable {
    /// Six weeks: a month view's full grid, Monday before the 1st to Sunday after the last.
    static let maxCalendarSpan: TimeInterval = 42 * 24 * 60 * 60
    /// Never-fetched shows hydrated per calendar request, so one call stays bounded.
    static let hydrationBudget = 10
    /// An in-progress item untouched this long is unfinished business (UPN-002).
    static let stalledAfter: TimeInterval = 30 * 24 * 60 * 60
    static let unfinishedLimit = 20

    let stores: Stores
    let catalog: CatalogService
    var now: @Sendable () -> Date = { Date() }

    func calendar(userID: UserID, from: Date, until: Date) async throws -> [CalendarEntry] {
        guard until > from, until.timeIntervalSince(from) <= Self.maxCalendarSpan else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "The range must be positive and at most 42 days.",
                details: ["to": "The range must be positive and at most 42 days."]
            )
        }
        try await hydrateNewShows(userID: userID)
        return try await stores.schedule.calendar(userID: userID, from: from, until: until, now: now())
    }

    func upNext(userID: UserID) async throws -> UpNext {
        try await hydrateNewShows(userID: userID)
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

    /// Shows whose episodes were never loaded (an import, a provider down at add time) get one
    /// attempt here, so a first calendar after an import is not empty. Stale-window refreshes
    /// belong to `CatalogRefresher`.
    private func hydrateNewShows(userID: UserID) async throws {
        let pending = try await stores.schedule.unhydratedTrackedShows(userID: userID, limit: Self.hydrationBudget)
        // Stamped first, like the refresher: a show the provider does not know (or an outage) is
        // tried once an hour, not on every calendar read. A few at once; the providers are paced.
        let (stores, catalog, now) = (stores, catalog, Date())
        _ = try await ImportService.boundedMap(pending, limit: 3) { titleID in
            try await stores.titles.markEpisodesAttempted(titleID, at: now)
            _ = try? await catalog.detail(titleID)
        }
    }
}
