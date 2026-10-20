import Foundation

/// CAT-010 · parses Fribb's `anime-list-full.json` (MIT, github.com/Fribb/anime-lists) into
/// AniList → TMDB/TVDB/MAL/AniDB mappings. Catalog data only, no user rows.
///
/// Only a TMDB *TV* id is kept: `TitleResolver` resolves a mapping as a TMDB show, so a film's
/// TMDB movie id would attach the anime to whichever show shares that number.
enum AnimeMappingLoader {
    /// The pinned source `aaru --anime-mappings` reads when given no other path or URL.
    static let defaultSource = "https://raw.githubusercontent.com/Fribb/anime-lists/master/anime-list-full.json"

    static func parse(_ data: Data) throws -> [AnimeMapping] {
        try JSONDecoder().decode([Entry].self, from: data).compactMap { entry in
            guard let anilist = entry.anilistID else { return nil }
            let tmdb = entry.themoviedbID?.tv
            return AnimeMapping(
                anilist: String(anilist),
                mal: entry.malID.map(String.init),
                anidb: entry.anidbID.map(String.init),
                tvdb: entry.tvdbID.map(String.init),
                tmdb: tmdb.map(String.init),
                tmdbSeason: tmdb == nil ? nil : entry.season?.tmdb
            )
        }
    }

    /// Reads a local path or an http(s) URL.
    static func load(from source: String, transport: any HTTPTransport) async throws -> Data {
        guard let url = URL(string: source), url.scheme == "https" || url.scheme == "http" else {
            return try Data(contentsOf: URL(fileURLWithPath: source))
        }
        let response = try await transport.send(OutboundRequest(url: url, timeout: .seconds(120)))
        guard response.status == 200 else { throw ProviderError(provider: "anime-lists", kind: .unavailable) }
        return response.body
    }

    private struct Entry: Decodable {
        struct TMDB: Decodable {
            let tv: Int?

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // A single id, or a list when one entry spans several TMDB records.
                tv = try (try? container.decodeIfPresent(Int.self, forKey: .tv))
                    ?? container.decodeIfPresent([Int].self, forKey: .tv)?.first
            }

            private enum CodingKeys: String, CodingKey { case tv }
        }

        struct Season: Decodable { let tmdb: Int? }

        let anilistID: Int?
        let malID: Int?
        let anidbID: Int?
        let tvdbID: Int?
        let themoviedbID: TMDB?
        let season: Season?

        private enum CodingKeys: String, CodingKey {
            case anilistID = "anilist_id"
            case malID = "mal_id"
            case anidbID = "anidb_id"
            case tvdbID = "tvdb_id"
            case themoviedbID = "themoviedb_id"
            case season
        }
    }
}
