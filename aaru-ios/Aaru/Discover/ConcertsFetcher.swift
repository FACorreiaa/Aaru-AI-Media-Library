import AaruAPI
import Foundation

/// One fetch for the Concerts view's Near list.
enum ConcertFetch {
    case page(ConcertPage), noPlace, failed, cancelled
}

/// A page of the Near list: everything around the centre (MUS-003), or one artist's concerts near
/// it or anywhere (MUS-010), read the same way by the list.
struct ConcertsFetcher {
    let api: Client
    /// "Use my location"'s point; nil uses the saved city.
    let point: ConcertPoint?
    let radius: ConcertRadius

    func near(page: Int) async throws -> ConcertFetch {
        let body = Components.Schemas.ConcertsNearRequest(
            latitude: point?.latitude, longitude: point?.longitude, radiusKm: radius, page: page
        )
        switch try await api.getConcertsNear(body: .json(body)) {
        case let .ok(response):
            let page = try response.body.json
            return Task.isCancelled ? .cancelled : .page(page)
        case let .default(statusCode, error):
            return Self.failure(statusCode, try? error.body.json.code)
        }
    }

    /// One artist's page, kept as a Near page.
    func search(_ artist: String, scope: ConcertSearchScope, page: Int) async throws -> ConcertFetch {
        guard let radiusKm = Components.Schemas.ConcertSearchRequest.RadiusKmPayload(rawValue: radius.rawValue) else {
            return .failed
        }
        let body = Components.Schemas.ConcertSearchRequest(
            q: artist, scope: scope, latitude: point?.latitude, longitude: point?.longitude, radiusKm: radiusKm,
            page: page
        )
        switch try await api.searchConcerts(body: .json(body)) {
        case let .ok(response):
            let found = try response.body.json
            let page = ConcertPage(
                place: found.place, radiusKm: found.radiusKm ?? radius.rawValue, items: found.items,
                page: found.page, hasMore: found.hasMore, unavailable: found.unavailable
            )
            return Task.isCancelled ? .cancelled : .page(page)
        case let .default(statusCode, error):
            return Self.failure(statusCode, try? error.body.json.code)
        }
    }

    private static func failure(_ statusCode: Int, _ code: String?) -> ConcertFetch {
        statusCode == 409 && code == "no_place" ? .noPlace : .failed
    }
}
