import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func getCalendar(_ input: Operations.GetCalendar.Input) async throws -> Operations.GetCalendar.Output {
        let entries = try await services.schedule.calendar(
            userID: currentUser(), from: input.query.from, until: input.query.to
        )
        return .ok(.init(body: .json(.init(items: entries.map(Components.Schemas.CalendarEntry.init)))))
    }

    func getUpNext(_: Operations.GetUpNext.Input) async throws -> Operations.GetUpNext.Output {
        let rows = try await services.schedule.upNext(userID: currentUser())
        return .ok(.init(body: .json(.init(
            continueWatching: rows.continueWatching.map(Components.Schemas.ContinueEntry.init),
            startWatching: rows.startWatching.map(Components.Schemas.StartEntry.init)
        ))))
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
            airsAt: entry.airsAt,
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
