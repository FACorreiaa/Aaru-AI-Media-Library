import AaruCore
import Foundation

/// Calendar (CAL-001) and Up Next (UPN-001). Both are derived reads over the library;
/// neither has a table of its own.
struct ScheduleService: Sendable {
    static let maxCalendarSpan: TimeInterval = 35 * 24 * 60 * 60
    /// Never-fetched shows hydrated per calendar request, so one call stays bounded.
    static let hydrationBudget = 10

    let stores: Stores
    let catalog: CatalogService
    var now: @Sendable () -> Date = { Date() }

    func calendar(userID: UserID, from: Date, until: Date) async throws -> [CalendarEntry] {
        guard until > from, until.timeIntervalSince(from) <= Self.maxCalendarSpan else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "The range must be positive and at most 35 days.",
                details: ["to": "The range must be positive and at most 35 days."]
            )
        }
        try await hydrateNewShows(userID: userID)
        return try await stores.schedule.calendar(userID: userID, from: from, until: until, now: now())
    }

    func upNext(userID: UserID) async throws -> (continueWatching: [ContinueEntry], startWatching: [StartEntry]) {
        try await hydrateNewShows(userID: userID)
        async let continuing = stores.schedule.continueWatching(userID: userID, now: now(), limit: 50)
        async let starting = stores.schedule.startWatching(userID: userID, limit: 20)
        return try await (continuing, starting)
    }

    /// Shows added before their episodes could be fetched (a provider was down) get one
    /// attempt here. Stale-window refreshes across the library belong to a job (JOB-001).
    private func hydrateNewShows(userID: UserID) async throws {
        let pending = try await stores.schedule.unhydratedTrackedShows(userID: userID, limit: Self.hydrationBudget)
        for titleID in pending {
            _ = try? await catalog.detail(titleID)
        }
    }
}
