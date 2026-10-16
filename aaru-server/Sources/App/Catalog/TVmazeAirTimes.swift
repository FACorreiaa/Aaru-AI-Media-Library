import AaruCore
import Foundation

/// Refines a show's episode list with exact air times and its network (CAT-011). TMDB stays the
/// episode source; this only replaces a date-only `airsAt` with the broadcast instant.
protocol AirTimeRefining: Sendable {
    func refine(_ episodes: CatalogEpisodes, ids: ExternalIDs) async throws -> CatalogEpisodes
}

/// TVmaze adapter (CAT-011): no key, ~20 calls / 10 s per IP. Shows are found by TVDB or IMDb id;
/// `airstamp` is the exact UTC instant. Data is CC BY-SA: credit TVmaze where it is shown
/// (PRV-001). No TVmaze field name leaves this file.
struct TVmazeAirTimes: AirTimeRefining {
    static let baseURL = URL(string: "https://api.tvmaze.com")!
    /// TVmaze and TMDB can number a season differently. A time is only trusted when its date is
    /// within this of TMDB's date for the same episode number.
    static let dateTolerance: TimeInterval = 2 * 24 * 60 * 60

    let client: ProviderClient

    func refine(_ episodes: CatalogEpisodes, ids: ExternalIDs) async throws -> CatalogEpisodes {
        guard let show = try await lookup(ids) else { return episodes }
        let listed = try await client.decode(
            [Episode].self, request("shows/\(show.id)/episodes", ["specials": "1"])
        )
        var stamps: [String: Date] = [:]
        for episode in listed {
            guard let season = episode.season, let number = episode.number,
                  let stamp = episode.airstamp.flatMap(Self.instant)
            else { continue }
            stamps["\(season)x\(number)"] = stamp
        }
        var refined = episodes
        refined.episodes = episodes.episodes.map { episode in
            guard let stamp = stamps["\(episode.season)x\(episode.episode)"] else { return episode }
            if let date = episode.airsAt, abs(stamp.timeIntervalSince(date)) > Self.dateTolerance {
                return episode
            }
            var exact = episode
            exact.airsAt = stamp
            exact.airTimeKnown = true
            return exact
        }
        // The broadcaster or streamer that premieres the show, which is what a viewer tunes to.
        refined.network = show.network?.name.nilIfBlank ?? show.webChannel?.name.nilIfBlank ?? episodes.network
        return refined
    }

    private func lookup(_ ids: ExternalIDs) async throws -> Show? {
        for case let (key, value?) in [("thetvdb", ids.tvdb), ("imdb", ids.imdb)] {
            do {
                return try await client.decode(Show.self, request("lookup/shows", [key: value]))
            } catch let error as ProviderError where error.kind == .notFound {
                continue
            }
        }
        return nil
    }

    private func request(_ path: String, _ query: [String: String]) -> OutboundRequest {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return OutboundRequest(url: components?.url ?? Self.baseURL, headers: [("Accept", "application/json")])
    }

    private static func instant(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

private struct Show: Decodable {
    struct Channel: Decodable { let name: String }

    let id: Int
    let network: Channel?
    let webChannel: Channel?
}

private struct Episode: Decodable {
    let season: Int?
    let number: Int?
    let airstamp: String?
}
