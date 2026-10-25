import Foundation

/// Ticketmaster's free tier allows 5,000 calls a day. Aaru stops at `limit` (UTC day) and serves
/// what it has cached, so a busy day never runs the key into its hard cap.
actor CallBudget {
    let limit: Int
    private var day = ""
    private var used = 0

    init(limit: Int) {
        self.limit = limit
    }

    /// Takes one call from today's budget; false when it is spent.
    func take(now: Date = Date()) -> Bool {
        let today = ISO8601DateFormatter.string(from: now, timeZone: .gmt, formatOptions: [.withFullDate])
        if today != day {
            day = today
            used = 0
        }
        guard used < limit else { return false }
        used += 1
        return true
    }
}

// swiftlint:disable inclusive_language
/// MUS-003 · Ticketmaster Discovery API v2: music events near a point or by performer, and
/// performers by name with their MusicBrainz links. Free key, 5,000 calls a day, 5 a second.
/// Terms: cache only for short periods, link out to Ticketmaster for tickets, never resell.
struct TicketmasterConcerts: ConcertListing {
    // swiftlint:enable inclusive_language
    static let baseURL = URL(string: "https://app.ticketmaster.com/discovery/v2")!
    /// 50 a page, and Ticketmaster refuses to page past 1,000 results.
    static let pageSize = 50
    static let maxPage = 10

    let client: ProviderClient
    let apiKey: String
    let budget: CallBudget

    func near(_ point: GeoPoint, radiusKm: Int, page: Int, from: Date) async throws -> ConcertResults {
        try await musicEvents(page: page, from: from, [
            "geoPoint": point.geohash(),
            "radius": String(radiusKm),
            "unit": "km",
        ])
    }

    func search(_ match: ConcertMatch, near: (point: GeoPoint, radiusKm: Int)?, page: Int, from: Date) async throws
        -> ConcertResults
    {
        var query: [String: String] = switch match {
        case let .keyword(keyword): ["keyword": keyword]
        case let .performer(id): ["attractionId": id]
        }
        if let near {
            query["geoPoint"] = near.point.geohash()
            query["radius"] = String(near.radiusKm)
            query["unit"] = "km"
        }
        return try await musicEvents(page: page, from: from, query)
    }

    func performing(_ attractionIDs: [String], from: Date) async throws -> [Concert] {
        guard !attractionIDs.isEmpty else { return [] }
        let response = try await get(EventPage.self, "events.json", [
            "attractionId": attractionIDs.joined(separator: ","),
            "sort": "date,asc",
            "startDateTime": Self.timestamp(from),
            "size": String(Self.pageSize),
        ])
        return response.events.compactMap(\.concert)
    }

    func attractions(named name: String) async throws -> [ConcertAttraction] {
        let response = try await get(AttractionPage.self, "attractions.json", [
            "keyword": name,
            "classificationName": "music",
            "size": "20",
        ])
        return (response.embedded?.attractions ?? []).map {
            ConcertAttraction(
                id: $0.id, name: $0.name,
                musicbrainzIDs: ($0.externalLinks?.musicbrainz ?? []).compactMap(\.id).map { $0.lowercased() },
                imageURL: pickImage($0.images, minWidth: 200)
            )
        }
    }

    /// One page of music events from `from` on, soonest first, narrowed by `query`.
    private func musicEvents(page: Int, from: Date, _ query: [String: String]) async throws -> ConcertResults {
        let response = try await get(EventPage.self, "events.json", query.merging([
            "classificationName": "music",
            "sort": "date,asc",
            "startDateTime": Self.timestamp(from),
            "size": String(Self.pageSize),
            "page": String(max(0, page - 1)),
        ]) { given, _ in given })
        let current = response.page?.number ?? 0
        let pages = response.page?.totalPages ?? 0
        return ConcertResults(
            concerts: response.events.compactMap(\.concert),
            hasMore: current + 1 < pages && current + 1 < Self.maxPage
        )
    }

    /// `2026-10-21T18:00:00Z`: Ticketmaster wants seconds and a literal Z, no fractions.
    static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter.string(from: date, timeZone: .gmt, formatOptions: [.withInternetDateTime])
    }

    private func get<T: Decodable>(_: T.Type, _ path: String, _ query: [String: String]) async throws -> T {
        guard await budget.take() else { throw ProviderError(provider: "ticketmaster", kind: .unavailable) }
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "apikey", value: apiKey)]
        guard let url = components?.url else { throw ProviderError(provider: "ticketmaster", kind: .malformed) }
        return try await client.decode(T.self, OutboundRequest(url: url, headers: [("Accept", "application/json")]))
    }
}

// MARK: - Ticketmaster wire shapes (private to this adapter)

private struct PageInfo: Decodable {
    let number: Int?
    let totalPages: Int?
}

private struct EventPage: Decodable {
    struct Embedded: Decodable {
        let events: [Event]?
    }

    let embedded: Embedded?
    let page: PageInfo?

    var events: [Event] {
        embedded?.events ?? []
    }

    enum CodingKeys: String, CodingKey {
        case page
        case embedded = "_embedded"
    }
}

private struct EventStart: Decodable {
    let localDate: String?
    let localTime: String?
    let dateTime: String?
    let timeTBA: Bool?
    let noSpecificTime: Bool?
}

private struct EventStatus: Decodable {
    let code: String?
}

private struct EventDates: Decodable {
    let start: EventStart?
    let status: EventStatus?
}

private struct EventImage: Decodable {
    let url: String
    let ratio: String?
    let width: Int?
    let fallback: Bool?
}

private struct Named: Decodable {
    let name: String?
}

/// Ticketmaster sends the coordinates as strings.
private struct VenueLocation: Decodable {
    let latitude: String?
    let longitude: String?

    var point: GeoPoint? {
        guard let latitude = latitude.flatMap(Double.init), let longitude = longitude.flatMap(Double.init) else {
            return nil
        }
        return GeoPoint(latitude: latitude, longitude: longitude)
    }
}

private struct Venue: Decodable {
    let name: String?
    let city: Named?
    let country: Named?
    let location: VenueLocation?
}

private struct Performer: Decodable {
    let name: String
}

private struct EventEmbedded: Decodable {
    let venues: [Venue]?
    let attractions: [Performer]?
}

private struct Event: Decodable {
    let id: String
    let name: String
    let url: String?
    let dates: EventDates?
    let images: [EventImage]?
    let distance: Double?
    let units: String?
    let embedded: EventEmbedded?

    enum CodingKeys: String, CodingKey {
        case id, name, url, dates, images, distance, units
        case embedded = "_embedded"
    }

    /// Nil for an event Aaru cannot show: no date, no ticket page, or cancelled.
    var concert: Concert? {
        guard let localDate = catalogDate(dates?.start?.localDate), let link = url.flatMap(URL.init(string:)),
              dates?.status?.code != "cancelled"
        else { return nil }
        let exactTime = dates?.start?.timeTBA != true && dates?.start?.noSpecificTime != true
        let venue = embedded?.venues?.first
        return Concert(
            id: id,
            name: name,
            artists: (embedded?.attractions ?? []).map(\.name),
            startsAt: exactTime ? dates?.start?.dateTime.flatMap { ISO8601DateFormatter().date(from: $0) } : nil,
            localDate: localDate,
            localTime: exactTime ? dates?.start?.localTime.map { String($0.prefix(5)) } : nil,
            venue: venue?.name,
            city: venue?.city?.name,
            country: venue?.country?.name,
            distanceKm: distance.map { units?.uppercased().hasPrefix("MI") == true ? $0 * 1.609344 : $0 },
            url: link,
            imageURL: poster,
            venuePoint: venue?.location?.point
        )
    }

    /// The event's poster: a wide image at least 500 px across.
    private var poster: URL? {
        pickImage(images, minWidth: 500)
    }
}

/// The smallest wide image at least `minWidth` across; Ticketmaster's own placeholders aside.
private func pickImage(_ images: [EventImage]?, minWidth: Int) -> URL? {
    let usable = (images ?? []).filter { $0.fallback != true }
    let wide = usable.filter { $0.ratio == "16_9" }.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
    let pick = wide.first { ($0.width ?? 0) >= minWidth } ?? wide.last ?? usable.first
    return pick.flatMap { URL(string: $0.url) }
}

private struct MusicBrainzLink: Decodable {
    let id: String?
}

private struct AttractionLinks: Decodable {
    let musicbrainz: [MusicBrainzLink]?
}

private struct Attraction: Decodable {
    let id: String
    let name: String
    let externalLinks: AttractionLinks?
    let images: [EventImage]?
}

private struct AttractionPage: Decodable {
    struct Embedded: Decodable {
        let attractions: [Attraction]?
    }

    let embedded: Embedded?

    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }
}
