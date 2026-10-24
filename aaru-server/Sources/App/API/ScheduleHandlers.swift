import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func getCalendar(_ input: Operations.GetCalendar.Input) async throws -> Operations.GetCalendar.Output {
        let userID = try currentUser()
        async let entries = services.schedule.calendar(userID: userID, from: input.query.from, until: input.query.to)
        async let pending = services.schedule.pendingShows(userID: userID)
        return try await .ok(.init(body: .json(.init(
            items: entries.map(Components.Schemas.CalendarEntry.init), pendingShows: pending
        ))))
    }

    func getUpNext(_: Operations.GetUpNext.Input) async throws -> Operations.GetUpNext.Output {
        try await .ok(.init(body: .json(.init(services.schedule.upNext(userID: currentUser())))))
    }
}

extension Components.Schemas.UpNext {
    init(_ rows: UpNext) {
        let counts = rows.counts
        self.init(
            continueWatching: rows.continueWatching.map(Components.Schemas.ContinueEntry.init),
            startWatching: rows.startWatching.map(Components.Schemas.StartEntry.init),
            counts: .init(
                wishlist: counts.wishlist, inProgress: counts.inProgress, finished: counts.finished,
                dropped: counts.dropped
            ),
            unfinished: rows.unfinished.map(Components.Schemas.UnfinishedEntry.init)
        )
    }
}

extension Components.Schemas.CalendarEntry {
    init(_ entry: CalendarEntry) {
        self.init(
            libraryItemId: entry.libraryItemID.description,
            title: .init(entry.title),
            season: entry.key.season,
            number: entry.key.episode,
            episodeName: entry.episodeName,
            episodeOverview: entry.episodeOverview,
            stillUrl: entry.stillURL?.absoluteString,
            airsAt: entry.airsAt,
            airTimeKnown: entry.airTimeKnown,
            runtimeMinutes: entry.runtimeMinutes,
            watched: entry.watched,
            kind: .init(rawValue: entry.kind.rawValue) ?? .regular
        )
    }
}

extension Components.Schemas.ContinueEntry {
    init(_ entry: ContinueEntry) {
        self.init(
            libraryItemId: entry.libraryItemID.description,
            title: .init(entry.title),
            next: .init(season: entry.next.season, number: entry.next.episode),
            nextName: entry.nextName,
            nextRuntimeMinutes: entry.nextRuntimeMinutes,
            remainingCount: entry.remainingCount,
            remainingMinutes: entry.remainingMinutes,
            isFinale: entry.isFinale
        )
    }
}

extension Components.Schemas.StartEntry {
    init(_ entry: StartEntry) {
        self.init(
            libraryItemId: entry.libraryItemID.description,
            title: .init(entry.title),
            runtimeMinutes: entry.runtimeMinutes
        )
    }
}

extension Components.Schemas.UnfinishedEntry {
    init(_ entry: UnfinishedEntry) {
        self.init(
            libraryItemId: entry.libraryItemID.description,
            title: .init(entry.title),
            reason: entry.reason == .dropped ? .dropped : .stalled,
            since: entry.since,
            next: entry.next.map { .init(season: $0.season, number: $0.episode) }
        )
    }
}
