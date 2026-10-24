import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

/// MUS-003 · concerts near a place and for the user's artists, and the "Concerts near" city.
extension APIImplementation {
    func getConcertsNear(_ input: Operations.GetConcertsNear.Input) async throws -> Operations.GetConcertsNear.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let userID = try currentUser()
        let page = try Self.concertPage(body.page)
        let point = try Self.oneOffPoint(body.latitude, body.longitude)
        let nearby: ConcertService.Nearby
        do {
            nearby = try await services.concerts.near(
                userID: userID, point: point, radiusKm: body.radiusKm.rawValue, page: page
            )
        } catch is NoConcertPlace {
            throw Self.noPlace
        }
        return .ok(.init(body: .json(.init(
            place: nearby.place.map { Components.Schemas.ConcertPlace($0) },
            radiusKm: nearby.radiusKm,
            items: nearby.results.concerts.map { Components.Schemas.Concert($0) },
            page: nearby.page,
            hasMore: nearby.results.hasMore,
            unavailable: nearby.unavailable
        ))))
    }

    func searchConcerts(_ input: Operations.SearchConcerts.Input) async throws -> Operations.SearchConcerts.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let userID = try currentUser()
        let query = body.q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2 ... 100).contains(query.count) else { throw Self.invalid("q", "Type 2 to 100 characters.") }
        let page = try Self.concertPage(body.page)
        let point = try Self.oneOffPoint(body.latitude, body.longitude)
        let scope: ConcertSearchScope = switch body.scope {
        case .near: .near
        case .anywhere: .anywhere
        }
        let found: ConcertService.Searched
        do {
            found = try await services.concerts.search(
                ConcertSearch(query: query, scope: scope, radiusKm: body.radiusKm.rawValue, page: page),
                userID: userID, point: point
            )
        } catch is NoConcertPlace {
            throw Self.noPlace
        }
        return .ok(.init(body: .json(.init(
            query: found.query,
            scope: found.scope == .near ? .near : .anywhere,
            place: found.place.map { Components.Schemas.ConcertPlace($0) },
            radiusKm: found.radiusKm,
            items: found.results.concerts.map { Components.Schemas.Concert($0) },
            page: found.page,
            hasMore: found.results.hasMore,
            unavailable: found.unavailable
        ))))
    }

    func getArtistConcerts(_: Operations.GetArtistConcerts.Input) async throws -> Operations.GetArtistConcerts.Output {
        let found = try await services.concerts.forLibrary(userID: currentUser())
        return .ok(.init(body: .json(.init(
            items: found.concerts.map { Components.Schemas.Concert($0) },
            matched: found.matched, pending: found.pending, unavailable: found.unavailable
        ))))
    }

    func searchConcertPlaces(
        _ input: Operations.SearchConcertPlaces.Input
    ) async throws -> Operations.SearchConcertPlaces.Output {
        _ = try currentUser()
        let query = input.query.q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2 ... 100).contains(query.count) else { throw Self.invalid("q", "Type 2 to 100 characters.") }
        let places = try await services.concerts.places(matching: query)
        return .ok(.init(body: .json(.init(items: places.map { Components.Schemas.ConcertPlace($0) }))))
    }

    func getConcertPlace(_: Operations.GetConcertPlace.Input) async throws -> Operations.GetConcertPlace.Output {
        let place = try await stores.concerts.place(userID: currentUser())
        return .ok(.init(body: .json(setting(place))))
    }

    func saveConcertPlace(_ input: Operations.SaveConcertPlace.Input) async throws -> Operations.SaveConcertPlace
        .Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let userID = try currentUser()
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1 ... 200).contains(name.count) else { throw Self.invalid("name", "1 to 200 characters.") }
        guard let point = GeoPoint(latitude: body.latitude, longitude: body.longitude) else {
            throw Self.invalid("latitude", "Not a position on Earth.")
        }
        let code = body.countryCode?.uppercased()
        guard code.map({ $0.count == 2 && $0.allSatisfy(\.isLetter) }) ?? true else {
            throw Self.invalid("countryCode", "Two letters, as ISO 3166-1.")
        }
        let place = ConcertPlace(
            name: name, region: Self.trimmed(body.region), country: Self.trimmed(body.country), countryCode: code,
            point: point
        )
        try await stores.concerts.savePlace(place, userID: userID, now: Date())
        return try await .ok(.init(body: .json(setting(stores.concerts.place(userID: userID)))))
    }

    func deleteConcertPlace(_: Operations.DeleteConcertPlace.Input) async throws -> Operations.DeleteConcertPlace
        .Output
    {
        try await stores.concerts.deletePlace(userID: currentUser())
        return .noContent(.init())
    }

    private func setting(_ place: ConcertPlace?) -> Components.Schemas.ConcertPlaceSetting {
        .init(place: place.map { Components.Schemas.ConcertPlace($0) }, available: services.concerts.isAvailable)
    }

    private static let noPlace = AppError(
        status: .conflict, code: "no_place", message: "Choose a city for concerts in Settings, or use your location."
    )

    private static func concertPage(_ page: Int?) throws -> Int {
        let page = page ?? 1
        guard (1 ... TicketmasterConcerts.maxPage).contains(page) else {
            throw invalid("page", "Pages run from 1 to \(TicketmasterConcerts.maxPage).")
        }
        return page
    }

    /// A one-off position sent with the request, rounded; nil when neither coordinate was sent.
    private static func oneOffPoint(_ latitude: Double?, _ longitude: Double?) throws -> GeoPoint? {
        switch (latitude, longitude) {
        case (nil, nil):
            return nil
        case let (latitude?, longitude?):
            guard let point = GeoPoint(latitude: latitude, longitude: longitude) else {
                throw invalid("latitude", "Not a position on Earth.")
            }
            return point
        default:
            throw invalid("longitude", "Send latitude and longitude together.")
        }
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(200))
    }

    private static func invalid(_ field: String, _ message: String) -> AppError {
        AppError(status: .unprocessableContent, code: "validation_failed", message: message, details: [field: message])
    }
}

extension Components.Schemas.Concert {
    init(_ concert: Concert) {
        self.init(
            id: concert.id, name: concert.name, artists: concert.artists, startsAt: concert.startsAt,
            localDate: concert.localDate, localTime: concert.localTime, venue: concert.venue, city: concert.city,
            country: concert.country, distanceKm: concert.distanceKm.map { ($0 * 10).rounded() / 10 },
            url: concert.url.absoluteString, imageUrl: concert.imageURL?.absoluteString
        )
    }
}

extension Components.Schemas.ConcertPlace {
    init(_ place: ConcertPlace) {
        self.init(
            name: place.name, region: place.region, country: place.country, countryCode: place.countryCode,
            latitude: place.point.latitude, longitude: place.point.longitude
        )
    }
}
