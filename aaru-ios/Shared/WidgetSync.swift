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

    /// Albums the Listening widget can show at most (medium shows four).
    static let listeningLimit = 8

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
        listening: [Components.Schemas.LibraryEntry],
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
            listening: albums(listening),
            writtenAt: now
        )
    }

    /// In-progress albums, most recently updated first, as the Listening widget draws them.
    static func albums(_ entries: [Components.Schemas.LibraryEntry]) -> [WidgetSnapshot.Album] {
        entries
            .filter { $0.title._type == .album && $0.status == .inProgress }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(listeningLimit)
            .map { entry in
                WidgetSnapshot.Album(
                    libraryItemId: entry.id,
                    title: entry.title.title,
                    artist: entry.title.byline,
                    year: entry.title.year,
                    coverURL: entry.title.posterUrl.flatMap(URL.init(string:))
                )
            }
    }

    /// Saves the snapshot and asks every placed widget to redraw. A snapshot built without the
    /// streak keeps the last one read.
    static func publish(_ snapshot: WidgetSnapshot) {
        var snapshot = snapshot
        if snapshot.streak == nil {
            snapshot.streak = WidgetSnapshotStore.load()?.streak
        }
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Fetches up next, the calendar window and the albums in progress, then publishes. Throws
    /// when up next or the calendar fails, so the last good snapshot stays; the albums failing
    /// alone keeps the last ones written.
    static func refresh(api: Client, now: Date = .now) async throws {
        let window = window(now: now)
        async let upNextOutput = api.getUpNext()
        async let calendarOutput = api.getCalendar(query: .init(from: window.lowerBound, to: window.upperBound))
        async let albums = listening(api: api)
        async let streak = streak(api: api)
        let (upNext, airing) = try await (upNextOutput, calendarOutput)
        guard case let .ok(upNextResponse) = upNext, case let .ok(airingResponse) = airing else {
            throw RefreshFailed()
        }
        var next = try snapshot(
            upNext: upNextResponse.body.json, airing: airingResponse.body.json.items, listening: [], now: now
        )
        next.listening = await albums ?? WidgetSnapshotStore.load()?.listening
        next.streak = await streak
        publish(next)
    }

    /// The streak (WID-007), or nil when the read failed; `publish` then keeps the last one.
    private static func streak(api: Client) async -> WidgetSnapshot.StreakState? {
        guard case let .ok(response) = try? await api.getProgress(),
              let streak = try? response.body.json.streak
        else { return nil }
        return WidgetSnapshot.StreakState(streak)
    }

    /// The albums being listened to, or nil when the read failed.
    private static func listening(api: Client) async -> [WidgetSnapshot.Album]? {
        let query = Operations.ListLibraryItems.Input.Query(_type: .album, status: .inProgress, limit: listeningLimit)
        guard case let .ok(response) = try? await api.listLibraryItems(query: query),
              let page = try? response.body.json
        else { return nil }
        return albums(page.items)
    }

    struct RefreshFailed: Error {}
}

extension WidgetSnapshot.StreakState {
    /// The widget's copy of `/v1/me/progress`'s streak: the run as its last day and length, and
    /// the active days of the last week for the bars.
    init(_ streak: Components.Schemas.StreakState) {
        let active = streak.days.filter(\.active).map(\.date)
        self.init(
            current: streak.current,
            longest: streak.longest,
            lastActive: streak.current > 0 ? active.max() : nil,
            active: active
        )
    }
}
