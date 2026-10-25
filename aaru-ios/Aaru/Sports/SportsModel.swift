import AaruAPI
import Foundation
import Observation

typealias SportEntity = Components.Schemas.SportEntity
typealias SportEntityKind = Components.Schemas.SportEntityKind
typealias SportEvent = Components.Schemas.SportEvent
typealias SportEventStatus = Components.Schemas.SportEventStatus
typealias SportSide = Components.Schemas.SportSide
typealias SportFavorite = Components.Schemas.SportFavorite
typealias SportFavorites = Components.Schemas.SportFavorites
typealias SportSchedule = Components.Schemas.SportSchedule
typealias SportScheduleGroup = Components.Schemas.SportScheduleGroup
typealias SportBroadcast = Components.Schemas.SportBroadcast
typealias SportEventDetail = Components.Schemas.SportEventDetail
typealias SportSettings = Components.Schemas.SportSettings

extension SportEntity {
    /// One follow's identity: kind and provider id ("team/133604").
    var followKey: String {
        "\(kind.rawValue)/\(id)"
    }

    /// "Team · Soccer · Arsenal": what it is, its sport, and its team or country when known.
    var detail: String {
        let kindLabel = switch kind {
        case .league: "League"
        case .team: "Team"
        case .player: "Player"
        }
        return [kindLabel, sport, teamName ?? country].compactMap(\.self).filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// Sports (SPT-004): the leagues, teams and players a user follows, with what is live, next and
/// last (Favorites), and one local day of their leagues' events (Schedule). Catalog data from
/// TheSportsDB through Aaru: never a Title, never a library write, never journaled.
@MainActor
@Observable
final class SportsModel {
    enum Section: String, CaseIterable, Identifiable {
        case favorites, schedule

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .favorites: "Favorites"
            case .schedule: "Schedule"
            }
        }
    }

    var section: Section = .favorites
    /// The date strip, three days back to seven ahead of the local today.
    private(set) var days: [SportDay]
    var day: SportDay

    private(set) var favorites: SportFavorites?
    private(set) var favoritesFailed = false
    private(set) var schedules: [String: SportSchedule] = [:]
    private(set) var failedDays: Set<String> = []
    private(set) var suggestions: [SportEntity] = []
    /// True once a response said Sports are off on this server.
    private(set) var unavailable = false
    /// Follows being written, by `followKey`.
    private(set) var changing: Set<String> = []
    /// Bumped when a follow changes, so the screen fetches what it shows again.
    private(set) var followRevision = 0
    var problem: String?

    /// A follow or unfollow made here, ahead of the next search or reload.
    @ObservationIgnored private var followOverrides: [String: Bool] = [:]
    @ObservationIgnored private let api: Client?

    init(api: Client?, now: Date = .now) {
        self.api = api
        let days = SportDay.strip(around: now)
        self.days = days
        day = days.first(where: \.isToday) ?? days[days.count / 2]
    }

    var schedule: SportSchedule? {
        schedules[day.key]
    }

    func isFollowing(_ entity: SportEntity) -> Bool {
        followOverrides[entity.followKey] ?? entity.following
    }

    /// After midnight the strip moves: today is today again, and the old days are dropped.
    func rollDays(now: Date = .now) {
        let fresh = SportDay.strip(around: now)
        guard fresh.first?.key != days.first?.key else { return }
        days = fresh
        day = fresh.first(where: { $0.key == day.key }) ?? fresh.first(where: \.isToday) ?? day
    }

    // MARK: Near-live

    /// Fetches the section on screen, then again while it matters: after about four seconds while
    /// the server is still fetching (a few times at most), and every 90 seconds while something
    /// shown is live. Returns when nothing needs it; the caller's task cancels it otherwise.
    func keepFresh() async {
        var policy = SportsRefresh()
        while !Task.isCancelled {
            let snapshot = await loadCurrent()
            guard let delay = policy.next(after: snapshot) else { return }
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
        }
    }

    /// Pull to refresh and ⌘R: the section on screen, once.
    func reload() async {
        await loadCurrent()
    }

    @discardableResult
    private func loadCurrent() async -> SportsRefresh.Snapshot? {
        switch section {
        case .favorites: await loadFavorites()
        case .schedule: await loadSchedule(day)
        }
    }

    // MARK: Loading

    @discardableResult
    func loadFavorites() async -> SportsRefresh.Snapshot? {
        guard let api else { return nil }
        do {
            switch try await api.getSportFavorites() {
            case let .ok(response):
                let favorites = try response.body.json
                self.favorites = favorites
                unavailable = favorites.unavailable
                favoritesFailed = false
                return SportsRefresh.Snapshot(favorites)
            case .default:
                favoritesFailed = favorites == nil
                if favorites != nil {
                    problem = "Favorites could not be refreshed."
                }
            }
        } catch {
            if !Self.isCancellation(error) {
                favoritesFailed = favorites == nil
            }
        }
        return nil
    }

    @discardableResult
    func loadSchedule(_ day: SportDay) async -> SportsRefresh.Snapshot? {
        guard let api else { return nil }
        let query = Operations.GetSportSchedule.Input.Query(date: day.key, tz: TimeZone.current.identifier)
        do {
            switch try await api.getSportSchedule(query: query) {
            case let .ok(response):
                let schedule = try response.body.json
                schedules[day.key] = schedule
                unavailable = schedule.unavailable
                failedDays.remove(day.key)
                return SportsRefresh.Snapshot(schedule)
            case .default:
                if schedules[day.key] == nil {
                    failedDays.insert(day.key)
                } else {
                    problem = "The schedule could not be refreshed."
                }
            }
        } catch {
            if !Self.isCancellation(error), schedules[day.key] == nil {
                failedDays.insert(day.key)
            }
        }
        return nil
    }

    /// The fixed picks for a first visit (the same for everyone; never a recommendation).
    func loadSuggestions() async {
        guard let api, suggestions.isEmpty,
              case let .ok(response) = try? await api.getSportSuggestions(),
              let list = try? response.body.json
        else { return }
        suggestions = list.items
        unavailable = list.unavailable
    }

    /// Leagues, teams and players for what was typed; nil when the search failed.
    func search(_ text: String, kind: SportEntityKind?) async -> [SportEntity]? {
        guard let api else { return [] }
        do {
            switch try await api.searchSports(query: .init(q: text, kind: kind)) {
            case let .ok(response):
                let list = try response.body.json
                unavailable = list.unavailable
                return list.items
            case .default:
                return nil
            }
        } catch {
            return nil
        }
    }

    /// One event with where to watch it; nil when it could not be loaded.
    func event(_ id: String) async -> SportEventDetail? {
        guard let api,
              case let .ok(response) = try? await api.getSportEvent(path: .init(id: id))
        else { return nil }
        return try? response.body.json
    }

    /// The "Where to watch" setting on the same server, for an event's country picker.
    func makeSettings() -> SportSettingsModel {
        SportSettingsModel(api: api)
    }

    // MARK: Following

    /// Follows or unfollows at once, and puts it back if the server says no.
    func setFollowing(_ entity: SportEntity, _ follow: Bool) async {
        let key = entity.followKey
        guard let api, !changing.contains(key) else { return }
        changing.insert(key)
        defer { changing.remove(key) }
        let previous = isFollowing(entity)
        followOverrides[key] = follow
        do {
            if follow {
                switch try await api.followSport(path: .init(kind: entity.kind, providerId: entity.id)) {
                case .ok:
                    followRevision += 1
                    problem = nil
                case let .default(statusCode, error):
                    followOverrides[key] = previous
                    problem = Self.followProblem(statusCode, error: try? error.body.json, name: entity.name)
                }
            } else {
                switch try await api.unfollowSport(path: .init(kind: entity.kind, providerId: entity.id)) {
                case .noContent:
                    favorites?.items.removeAll { $0.entity.followKey == key }
                    followRevision += 1
                    problem = nil
                case let .default(statusCode, error):
                    followOverrides[key] = previous
                    problem = Self.followProblem(statusCode, error: try? error.body.json, name: entity.name)
                }
            }
        } catch {
            followOverrides[key] = previous
            problem = "\(entity.name) was not changed. Aaru could not reach the server."
        }
    }

    static func followProblem(_ statusCode: Int, error: Components.Schemas.ErrorResponse?, name: String) -> String {
        switch (statusCode, error?.code) {
        case (409, "too_many_follows"):
            "You follow 100 already. Unfollow one to add \(name)."
        case (503, _):
            "Sports aren't answering right now. Try again in a few minutes."
        default:
            error?.message ?? "\(name) was not changed."
        }
    }

    /// A newer request (another day, the view leaving) cancels the one in flight: not a failure.
    private static func isCancellation(_ error: any Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

/// The "Where to watch" country and whether this server has Sports at all. The Sports tab shows
/// only when it does; Settings → Friends & privacy and an event's "Where to watch" edit the
/// country through it.
@MainActor
@Observable
final class SportSettingsModel {
    private(set) var settings: SportSettings?
    private(set) var isSaving = false
    var problem: String?

    @ObservationIgnored private let api: Client?

    init(api: Client?) {
        self.api = api
    }

    var available: Bool {
        settings?.available ?? false
    }

    var countryCode: String? {
        settings?.watchCountryCode
    }

    /// Whether this server has Sports on; false when it could not be asked.
    static func isAvailable(api: Client?) async -> Bool {
        let model = SportSettingsModel(api: api)
        await model.load()
        return model.available
    }

    /// A failure leaves Sports hidden.
    func load() async {
        guard let api, case let .ok(response) = try? await api.getSportSettings(),
              let settings = try? response.body.json
        else { return }
        self.settings = settings
    }

    /// Saves the country, or clears it with nil. Returns whether it was saved.
    func save(_ code: String?) async -> Bool {
        guard let api else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            switch try await api.saveSportSettings(body: .json(.init(watchCountryCode: code))) {
            case let .ok(response):
                settings = try response.body.json
                problem = nil
                return true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "The country was not saved."
            }
        } catch {
            problem = "The country was not saved. Aaru could not reach the server."
        }
        return false
    }
}
