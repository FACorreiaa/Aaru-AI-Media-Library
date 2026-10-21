import Foundation

/// MUS-003 · Open-Meteo's geocoder turns the city a user types for "Concerts near" into a point.
/// No key; free for non-commercial use (revisit if Aaru charges). Only the typed name is sent.
struct OpenMeteoPlaces: PlaceSearching {
    static let baseURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search")!

    let client: ProviderClient

    func places(matching query: String) async throws -> [ConcertPlace] {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "8"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else { throw ProviderError(provider: "open-meteo", kind: .malformed) }
        let page = try await client.decode(
            SearchPage.self, OutboundRequest(url: url, headers: [("Accept", "application/json")])
        )
        return (page.results ?? []).compactMap { result in
            GeoPoint(latitude: result.latitude, longitude: result.longitude).map {
                ConcertPlace(
                    name: result.name, region: result.admin1, country: result.country,
                    countryCode: result.countryCode?.uppercased(), point: $0
                )
            }
        }
    }
}

private struct PlaceResult: Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let countryCode: String?
    let admin1: String?

    enum CodingKeys: String, CodingKey {
        case name, latitude, longitude, country, admin1
        case countryCode = "country_code"
    }
}

private struct SearchPage: Decodable {
    /// Absent, not empty, when nothing matches.
    let results: [PlaceResult]?
}
