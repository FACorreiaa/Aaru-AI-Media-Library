import AaruAPI
import Foundation
import WidgetKit

/// A `/v1` client for code that runs outside the app's session handling: the widgets' intents and
/// the background refresh. It reads the shared Keychain token on every call and never signs anyone
/// out; a 401 just fails the call, and the app is the one that ends a session.
enum SharedAPI {
    static var baseURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "AaruAPIBaseURL") as? String).flatMap(URL.init(string:))
    }

    /// Nil when nobody is signed in on this device or the build has no server.
    static func client() -> Client? {
        let keychain = SessionKeychain()
        guard let baseURL, keychain.read() != nil else { return nil }
        return Client.aaru(
            baseURL: baseURL,
            session: SessionMiddleware(token: { keychain.read() }, onUnauthorized: {})
        )
    }
}

/// Builds and publishes the widget snapshot (WID-001).
enum WidgetSync {
    /// How far ahead the widgets look.
    static let horizon: TimeInterval = 14 * 86400

    /// The calendar window: from the Monday of this week (for the week widget) or yesterday,
    /// whichever is earlier — a date-only air date is midnight UTC, "yesterday" west of
    /// Greenwich — to two weeks out. Never more than CAL-001's 42 days.
    static func window(now: Date, calendar: Calendar = WidgetSnapshot.weekCalendar) -> Range<Date> {
        let today = calendar.startOfDay(for: now)
        let monday = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = min(monday, today.addingTimeInterval(-86400))
        return start ..< today.addingTimeInterval(horizon)
    }

    static func snapshot(
        upNext: Components.Schemas.UpNext,
        airing: [Components.Schemas.CalendarEntry],
        now: Date
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            upNext: upNext.continueWatching.map { entry in
                WidgetSnapshot.NextEpisode(
                    libraryItemId: entry.libraryItemId,
                    title: entry.title.title,
                    season: entry.next.season,
                    number: entry.next.number,
                    episodeName: entry.nextName,
                    runtimeMinutes: entry.nextRuntimeMinutes,
                    remainingCount: entry.remainingCount,
                    remainingMinutes: entry.remainingMinutes,
                    isFinale: entry.isFinale,
                    posterURL: entry.title.posterUrl.flatMap(URL.init(string:)),
                    backdropURL: entry.title.backdropUrl.flatMap(URL.init(string:))
                )
            },
            airings: airing.sorted { $0.airsAt < $1.airsAt }.map { entry in
                WidgetSnapshot.Airing(
                    libraryItemId: entry.libraryItemId,
                    title: entry.title.title,
                    season: entry.season,
                    number: entry.number,
                    episodeName: entry.episodeName,
                    airsAt: entry.airsAt,
                    airTimeKnown: entry.airTimeKnown,
                    network: entry.title.network,
                    kind: AiringKind(rawValue: entry.kind.rawValue) ?? .regular,
                    watched: entry.watched
                )
            },
            writtenAt: now
        )
    }

    /// Saves the snapshot and asks every placed widget to redraw.
    static func publish(_ snapshot: WidgetSnapshot) {
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Fetches up next and the calendar window, then publishes. Throws when either read fails, so
    /// the last good snapshot stays.
    static func refresh(api: Client, now: Date = .now) async throws {
        let window = window(now: now)
        async let upNextOutput = api.getUpNext()
        async let calendarOutput = api.getCalendar(query: .init(from: window.lowerBound, to: window.upperBound))
        let (upNext, airing) = try await (upNextOutput, calendarOutput)
        guard case let .ok(upNextResponse) = upNext, case let .ok(airingResponse) = airing else {
            throw RefreshFailed()
        }
        try publish(snapshot(upNext: upNextResponse.body.json, airing: airingResponse.body.json.items, now: now))
    }

    struct RefreshFailed: Error {}
}
