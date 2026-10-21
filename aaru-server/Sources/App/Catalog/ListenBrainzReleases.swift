import AaruCore
import Foundation

/// Discover's album rows (MUS-002) from ListenBrainz, no key. Fresh releases carry no listen
/// counts of their own, so each list is ranked by what ListenBrainz users play this month:
/// New albums are this month's most-played release groups that came out in the last 30 days;
/// Coming soon is the next 30 days of releases by this month's most-played artists, soonest
/// first. Albums and EPs with a cover only, never compilations of others, live records or
/// spoken word. The same rows for everyone.
struct ListenBrainzReleases: DiscoverListing {
    static let baseURL = URL(string: "https://api.listenbrainz.org/1")!
    /// "Various Artists" is credited on compilations; it is not an artist anyone follows.
    static let variousArtists = "89ad4ac3-39f7-470e-963a-56509c546377"
    static let window = "30"
    static let statsCount = "1000"

    let client: ProviderClient
    let userAgent: String

    var discoverLists: Set<DiscoverList> {
        [.musicNew, .musicUpcoming]
    }

    func list(_ list: DiscoverList, now _: Date) async throws -> [CatalogHit] {
        switch list {
        case .musicNew: try await newAlbums()
        case .musicUpcoming: try await upcoming()
        default: throw ProviderError(provider: "listenbrainz", kind: .notFound)
        }
    }

    private func newAlbums() async throws -> [CatalogHit] {
        async let fresh = releases(past: true)
        async let played = get(
            Stats<TopReleaseGroups>.self, "stats/sitewide/release-groups",
            ["range": "this_month", "count": Self.statsCount]
        )
        let byGroup = try await Dictionary(
            fresh.filter(\.isTracked).map { ($0.releaseGroupMbid, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return try await played.payload.releaseGroups
            .sorted { $0.listenCount > $1.listenCount }
            .compactMap { $0.releaseGroupMbid.flatMap { byGroup[$0] }?.hit }
    }

    private func upcoming() async throws -> [CatalogHit] {
        async let fresh = releases(past: false)
        async let played = get(
            Stats<TopArtists>.self, "stats/sitewide/artists", ["range": "this_month", "count": Self.statsCount]
        )
        var rank: [String: Int] = [:]
        for (index, artist) in try await played.payload.artists.enumerated() {
            if let mbid = artist.artistMbid, mbid != Self.variousArtists, rank[mbid] == nil {
                rank[mbid] = index
            }
        }
        let known = rank
        return try await fresh
            .filter(\.isTracked)
            .compactMap { release -> (release: FreshRelease, rank: Int)? in
                (release.artistMbids ?? []).compactMap { known[$0] }.min().map { (release, $0) }
            }
            .sorted { ($0.release.releaseDate, $0.rank) < ($1.release.releaseDate, $1.rank) }
            .map(\.release.hit)
    }

    private func releases(past: Bool) async throws -> [FreshRelease] {
        try await get(FreshPage.self, "explore/fresh-releases/", [
            "days": Self.window, "past": past ? "true" : "false", "future": past ? "false" : "true",
        ]).payload.releases
    }

    private func get<T: Decodable>(_: T.Type, _ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw ProviderError(provider: "listenbrainz", kind: .malformed) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try await client.decode(
            T.self,
            OutboundRequest(url: url, headers: [("User-Agent", userAgent), ("Accept", "application/json")]),
            decoder: decoder
        )
    }
}

// MARK: - ListenBrainz wire shapes (private to this adapter)

private struct FreshPage: Decodable {
    struct Payload: Decodable {
        let releases: [FreshRelease]
    }

    let payload: Payload
}

private struct FreshRelease: Decodable {
    let artistCreditName: String
    let artistMbids: [String]?
    let caaId: Int?
    let caaReleaseMbid: String?
    let releaseDate: String
    let releaseGroupMbid: String
    let releaseGroupPrimaryType: String?
    let releaseGroupSecondaryType: String?
    let releaseName: String

    /// An album or an EP of new work, with a cover to show.
    var isTracked: Bool {
        releaseGroupPrimaryType.map(MusicBrainzCatalog.trackedTypes.contains) == true
            && releaseGroupSecondaryType == nil && caaId != nil && caaReleaseMbid != nil
    }

    var hit: CatalogHit {
        CatalogHit(
            type: .album, title: releaseName, originalTitle: nil, year: catalogYear(releaseDate),
            posterURL: caaReleaseMbid.flatMap { release in
                caaId.flatMap { URL(string: "https://coverartarchive.org/release/\(release)/\($0)-250.jpg") }
            },
            overview: nil, byline: artistCreditName, ids: ExternalIDs(musicbrainz: releaseGroupMbid), isAnime: false,
            releaseDate: catalogDate(releaseDate)
        )
    }
}

private struct Stats<Payload: Decodable>: Decodable {
    let payload: Payload
}

private struct TopReleaseGroups: Decodable {
    struct Group: Decodable {
        let releaseGroupMbid: String?
        let listenCount: Int
    }

    let releaseGroups: [Group]
}

private struct TopArtists: Decodable {
    struct Artist: Decodable {
        let artistMbid: String?
    }

    let artists: [Artist]
}
