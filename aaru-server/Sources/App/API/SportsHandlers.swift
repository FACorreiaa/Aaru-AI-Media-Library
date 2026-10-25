import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

/// SPT-002 · the Sports tab: follows, favorites, one day's schedule, one event and where to
/// watch it. Sports only: nothing here touches the library, the journal or friends.
extension APIImplementation {
    func getSportSuggestions(
        _: Operations.GetSportSuggestions.Input
    ) async throws -> Operations.GetSportSuggestions.Output {
        let userID = try currentUser()
        let following = try await followed(userID)
        let picks = await services.sports.suggestions()
        return .ok(.init(body: .json(.init(
            items: picks.map { Components.Schemas.SportEntity($0, following: following) },
            unavailable: !services.sports.isAvailable
        ))))
    }

    func searchSports(_ input: Operations.SearchSports.Input) async throws -> Operations.SearchSports.Output {
        let userID = try currentUser()
        let query = input.query.q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2 ... 100).contains(query.count) else { throw Self.sportsInvalid("q", "Type 2 to 100 characters.") }
        guard services.sports.isAvailable else { return .ok(.init(body: .json(.init(items: [], unavailable: true)))) }
        let found = try await services.sports.search(query, kind: input.query.kind.map(SportEntityKind.init))
        let following = try await followed(userID)
        return .ok(.init(body: .json(.init(
            items: found.map { Components.Schemas.SportEntity($0, following: following) }, unavailable: false
        ))))
    }

    func getSportFavorites(_: Operations.GetSportFavorites.Input) async throws -> Operations.GetSportFavorites.Output {
        let favorites = try await services.sports.favorites(userID: currentUser())
        return .ok(.init(body: .json(.init(
            items: favorites.items.map { favorite in
                .init(
                    entity: .init(favorite.entity, following: [Self.followKey(favorite.entity)]),
                    live: favorite.live.map { .init($0) },
                    next: favorite.next.map { .init($0) },
                    last: favorite.last.map { .init($0) },
                    pending: favorite.pending
                )
            },
            unavailable: favorites.unavailable
        ))))
    }

    func getSportSchedule(_ input: Operations.GetSportSchedule.Input) async throws -> Operations.GetSportSchedule
        .Output
    {
        let userID = try currentUser()
        let zone: TimeZone
        if let name = input.query.tz {
            guard let given = TimeZone(identifier: name) else {
                throw Self.sportsInvalid("tz", "An IANA time zone, like Europe/Lisbon.")
            }
            zone = given
        } else {
            zone = .gmt
        }
        guard SportsService.startOfDay(input.query.date, in: zone) != nil else {
            throw Self.sportsInvalid("date", "A day as YYYY-MM-DD.")
        }
        let schedule = try await services.sports.schedule(userID: userID, date: input.query.date, timeZone: zone)
        return .ok(.init(body: .json(.init(
            date: schedule.date,
            groups: schedule.groups.map { group in
                .init(
                    leagueId: group.leagueID, league: group.league, sport: group.sport,
                    badgeUrl: group.badgeURL?.absoluteString,
                    events: group.events.map { .init($0.event, isFavorite: $0.isFavorite) }
                )
            },
            pending: schedule.pending,
            unavailable: schedule.unavailable
        ))))
    }

    func getSportEvent(_ input: Operations.GetSportEvent.Input) async throws -> Operations.GetSportEvent.Output {
        let userID = try currentUser()
        let id = input.path.id
        guard (1 ... 40).contains(id.count), id.allSatisfy(\.isNumber) else { throw AppError.notFound() }
        let detail: SportsService.EventDetail?
        do {
            detail = try await services.sports.event(id: id, userID: userID)
        } catch is SportsOff {
            throw Self.sportsOff()
        }
        guard let detail else { throw AppError.notFound("No such event.") }
        return .ok(.init(body: .json(.init(
            event: .init(detail.event, isFavorite: detail.isFavorite),
            inYourCountry: detail.inYourCountry.map { .init($0) },
            elsewhere: detail.elsewhere.map { .init($0) },
            watchCountryCode: detail.watchCountryCode
        ))))
    }

    func listSportFollows(_: Operations.ListSportFollows.Input) async throws -> Operations.ListSportFollows.Output {
        let follows = try await services.sports.follows(userID: currentUser())
        return .ok(.init(body: .json(.init(
            items: follows.map { Components.Schemas.SportEntity($0, following: [Self.followKey($0)]) }
        ))))
    }

    func followSport(_ input: Operations.FollowSport.Input) async throws -> Operations.FollowSport.Output {
        let userID = try currentUser()
        let id = input.path.providerId
        guard (1 ... 40).contains(id.count), id.allSatisfy(\.isNumber) else { throw AppError.notFound() }
        do {
            let entity = try await services.sports.follow(.init(input.path.kind), id: id, userID: userID)
            return .ok(.init(body: .json(.init(entity, following: [Self.followKey(entity)]))))
        } catch is SportsOff {
            throw Self.sportsOff()
        } catch is UnknownSportEntity {
            throw AppError.notFound("The sports provider does not know that one.")
        } catch is TooManySportFollows {
            throw AppError(
                status: .conflict, code: "too_many_follows",
                message: "You can follow up to \(SportsService.followLimit) in Sports. Unfollow one first."
            )
        }
    }

    func unfollowSport(_ input: Operations.UnfollowSport.Input) async throws -> Operations.UnfollowSport.Output {
        try await services.sports.unfollow(.init(input.path.kind), id: input.path.providerId, userID: currentUser())
        return .noContent(.init())
    }

    func getSportSettings(_: Operations.GetSportSettings.Input) async throws -> Operations.GetSportSettings.Output {
        let code = try await services.sports.watchCountry(userID: currentUser())
        return .ok(.init(body: .json(.init(watchCountryCode: code, available: services.sports.isAvailable))))
    }

    func saveSportSettings(_ input: Operations.SaveSportSettings.Input) async throws -> Operations.SaveSportSettings
        .Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let userID = try currentUser()
        let code = body.watchCountryCode?.trimmingCharacters(in: .whitespaces).uppercased()
        let chosen = code?.isEmpty == true ? nil : code
        guard chosen.map({ $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isLetter } }) ?? true else {
            throw Self.sportsInvalid("watchCountryCode", "Two letters, as ISO 3166-1.")
        }
        try await services.sports.saveWatchCountry(chosen, userID: userID)
        let saved = try await services.sports.watchCountry(userID: userID)
        return .ok(.init(body: .json(.init(watchCountryCode: saved, available: services.sports.isAvailable))))
    }

    private func followed(_ userID: UserID) async throws -> Set<String> {
        try await Set(services.sports.follows(userID: userID).map(Self.followKey))
    }

    static func followKey(_ entity: SportEntity) -> String {
        "\(entity.kind.rawValue):\(entity.id)"
    }

    private static func sportsOff() -> AppError {
        AppError(status: .serviceUnavailable, code: "sports_unavailable", message: "Sports are not set up yet.")
    }

    private static func sportsInvalid(_ field: String, _ message: String) -> AppError {
        AppError(status: .unprocessableContent, code: "validation_failed", message: message, details: [field: message])
    }
}

extension SportEntityKind {
    init(_ kind: Components.Schemas.SportEntityKind) {
        switch kind {
        case .league: self = .league
        case .team: self = .team
        case .player: self = .player
        }
    }
}

extension Components.Schemas.SportEntity {
    init(_ entity: SportEntity, following: Set<String>) {
        self.init(
            kind: .init(entity.kind), id: entity.id, name: entity.name, sport: entity.sport,
            badgeUrl: entity.badgeURL?.absoluteString, country: entity.country, leagueId: entity.leagueID,
            teamId: entity.teamID, teamName: entity.teamName,
            following: following.contains(APIImplementation.followKey(entity))
        )
    }
}

extension Components.Schemas.SportEntityKind {
    init(_ kind: SportEntityKind) {
        switch kind {
        case .league: self = .league
        case .team: self = .team
        case .player: self = .player
        }
    }
}

extension Components.Schemas.SportEvent {
    init(_ event: SportEvent, isFavorite: Bool = false) {
        self.init(
            id: event.id, sport: event.sport, name: event.name, leagueId: event.leagueID, league: event.league,
            leagueBadgeUrl: event.leagueBadgeURL?.absoluteString, home: event.home.map { .init($0) },
            away: event.away.map { .init($0) }, startsAt: event.startsAt, day: event.day,
            status: .init(event.status), progress: event.progress, venue: event.venue, round: event.round,
            imageUrl: event.imageURL?.absoluteString, isFavorite: isFavorite
        )
    }
}

extension Components.Schemas.SportSide {
    init(_ side: SportSide) {
        self.init(id: side.id, name: side.name, badgeUrl: side.badgeURL?.absoluteString, score: side.score)
    }
}

extension Components.Schemas.SportEventStatus {
    init(_ status: SportEventStatus) {
        switch status {
        case .scheduled: self = .scheduled
        case .live: self = .live
        case .finished: self = .finished
        case .postponed: self = .postponed
        case .cancelled: self = .cancelled
        }
    }
}

extension Components.Schemas.SportBroadcast {
    init(_ broadcast: SportBroadcast) {
        self.init(channel: broadcast.channel, country: broadcast.country, logoUrl: broadcast.logoURL?.absoluteString)
    }
}
