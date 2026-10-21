import AaruCore
import Foundation

/// MusicBrainz adapter (MUS-001): albums and EPs as release groups, the artist credit, genres,
/// and a tracklist from the release group's earliest official release. Covers are Cover Art
/// Archive URLs, referenced, never downloaded. MusicBrainz allows one request a second and
/// asks every client to identify itself.
struct MusicBrainzCatalog: CatalogSearching, TrackListing, AlbumArtistListing {
    static let baseURL = URL(string: "https://musicbrainz.org/ws/2")!
    /// The types Aaru tracks: albums and EPs, not singles, broadcasts or compilations of others.
    static let trackedTypes: Set<String> = ["Album", "EP"]

    let client: ProviderClient
    let userAgent: String

    static func coverURL(releaseGroup mbid: String) -> URL? {
        URL(string: "https://coverartarchive.org/release-group/\(mbid)/front-250")
    }

    func search(query: String, type _: MediaType) async throws -> [CatalogHit] {
        // Lucene syntax: the user's words match the album or its artist; their punctuation is
        // escaped so it is never query syntax.
        let terms = Self.luceneEscaped(query)
        let lucene = "(releasegroup:(\(terms)) OR artist:(\(terms))) AND (primarytype:album OR primarytype:ep)"
        let page = try await get(SearchPage.self, "release-group", ["query": lucene, "limit": "25"])
        return page.releaseGroups.filter(\.isTracked).map(\.hit)
    }

    static func luceneEscaped(_ text: String) -> String {
        let special = Set("+-&|!(){}[]^\"~*?:\\/")
        return String(text.flatMap { special.contains($0) ? ["\\", $0] : [$0] })
    }

    func hydrate(ids: ExternalIDs, type _: MediaType) async throws -> CatalogTitle? {
        guard let mbid = ids.musicbrainz else { return nil }
        let group: ReleaseGroup
        do {
            group = try await get(ReleaseGroup.self, "release-group/\(mbid)", ["inc": "artist-credits+genres"])
        } catch let error as ProviderError where error.kind == .notFound {
            return nil
        }
        var hit = group.hit
        hit.ids = hit.ids.filling(from: ids)
        let genres = (group.genres ?? []).sorted { $0.count > $1.count }.prefix(5).map(\.name)
        return CatalogTitle(hit: hit, status: nil, runtimeMinutes: nil, genres: genres)
    }

    /// MUS-003: the album's credited artists, for matching concerts by MusicBrainz id.
    func artists(releaseGroup mbid: String) async throws -> [MusicArtist]? {
        let group: ReleaseGroup
        do {
            group = try await get(ReleaseGroup.self, "release-group/\(mbid)", ["inc": "artist-credits"])
        } catch let error as ProviderError where error.kind == .notFound {
            return nil
        }
        var seen = Set<String>()
        return (group.artistCredit ?? []).compactMap { credit in
            guard let artist = credit.artist, seen.insert(artist.id).inserted else { return nil }
            return MusicArtist(musicbrainzID: artist.id.lowercased(), name: artist.name)
        }
    }

    func tracks(ids: ExternalIDs) async throws -> [AlbumTrack]? {
        guard let mbid = ids.musicbrainz else { return nil }
        let page = try await get(ReleasePage.self, "release", [
            "release-group": mbid, "status": "official", "inc": "recordings", "limit": "25",
        ])
        // The earliest dated release stands for the album; undated ones come last.
        guard let release = page.releases.min(by: { ($0.date ?? "9999") < ($1.date ?? "9999") }) else { return [] }
        return release.media.enumerated().flatMap { index, medium in
            (medium.tracks ?? []).enumerated().map { trackIndex, track in
                AlbumTrack(
                    disc: medium.position ?? index + 1,
                    position: track.position ?? trackIndex + 1,
                    name: track.title,
                    lengthMs: track.length
                )
            }
        }
    }

    func get<T: Decodable>(_: T.Type, _ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        var items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "fmt", value: "json"))
        components?.queryItems = items
        guard let url = components?.url else { throw ProviderError(provider: "musicbrainz", kind: .malformed) }
        return try await client.decode(
            T.self,
            OutboundRequest(url: url, headers: [("User-Agent", userAgent), ("Accept", "application/json")]),
            decoder: JSONDecoder()
        )
    }
}

/// One track of an album's tracklist.
struct AlbumTrack: Sendable, Equatable {
    var disc: Int
    var position: Int
    var name: String
    var lengthMs: Int?
}

/// A provider that lists an album's tracks.
protocol TrackListing: Sendable {
    /// The tracklist for an album it can identify from `ids`; nil when it cannot.
    func tracks(ids: ExternalIDs) async throws -> [AlbumTrack]?
}

// MARK: - MusicBrainz wire shapes (private to this adapter)

private struct ArtistCredit: Decodable {
    struct Artist: Decodable {
        let id: String
        let name: String
    }

    let name: String
    let joinphrase: String?
    let artist: Artist?
}

private struct ReleaseGroup: Decodable {
    struct Genre: Decodable {
        let name: String
        let count: Int
    }

    let id: String
    let title: String
    let primaryType: String?
    let firstReleaseDate: String?
    let artistCredit: [ArtistCredit]?
    let genres: [Genre]?

    enum CodingKeys: String, CodingKey {
        case id, title, genres
        case primaryType = "primary-type"
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
    }

    var isTracked: Bool {
        primaryType.map(MusicBrainzCatalog.trackedTypes.contains) ?? false
    }

    /// "Simon & Garfunkel", "Jay-Z feat. Alicia Keys": the credit as MusicBrainz joins it.
    var byline: String? {
        guard let credit = artistCredit, !credit.isEmpty else { return nil }
        return credit.map { $0.name + ($0.joinphrase ?? "") }.joined()
    }

    var hit: CatalogHit {
        CatalogHit(
            type: .album, title: title, originalTitle: nil, year: catalogYear(firstReleaseDate),
            posterURL: MusicBrainzCatalog.coverURL(releaseGroup: id), overview: nil, byline: byline,
            ids: ExternalIDs(musicbrainz: id), isAnime: false, releaseDate: catalogDate(firstReleaseDate)
        )
    }
}

private struct SearchPage: Decodable {
    let releaseGroups: [ReleaseGroup]

    enum CodingKeys: String, CodingKey { case releaseGroups = "release-groups" }
}

private struct ReleasePage: Decodable {
    struct Release: Decodable {
        let date: String?
        let media: [Medium]
    }

    struct Medium: Decodable {
        let position: Int?
        let tracks: [Track]?
    }

    struct Track: Decodable {
        let position: Int?
        let title: String
        let length: Int?
    }

    let releases: [Release]
}
