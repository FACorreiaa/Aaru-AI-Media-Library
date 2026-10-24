import AaruCore
import Foundation

// MARK: - On the air (DISC-003, CAT-014)

extension TMDBCatalog: OnAirListing {
    /// The guide covers this many shows: two on-the-air pages, after the row filter.
    static let onAirLimit = 40
    static let logoBase = "https://image.tmdb.org/t/p/w92"

    /// TMDB's on-the-air shows (an episode within the next week) with their next episode, first
    /// network and streaming services in every region, one detail call each.
    func onAir(now: Date) async throws -> [OnAirShow] {
        var hits: [CatalogHit] = []
        for page in 1 ... 2 {
            let (found, hasMore) = try await onAirPage(page)
            hits += found
            if !hasMore {
                break
            }
        }
        var seen: Set<String> = []
        let unique = hits.filter { $0.ids.tmdb.map { seen.insert($0).inserted } ?? false }.prefix(Self.onAirLimit)
        // A week back covers a show whose next episode TMDB has not rolled over yet.
        let window = now.addingTimeInterval(-24 * 60 * 60) ... now.addingTimeInterval(8 * 24 * 60 * 60)
        return try await withThrowingTaskGroup(of: (Int, OnAirShow?).self) { group in
            for (index, hit) in unique.enumerated() {
                guard let tmdb = hit.ids.tmdb else { continue }
                group.addTask {
                    let detail: OnAirDetail
                    do {
                        detail = try await get(
                            OnAirDetail.self, "tv/\(tmdb)", ["append_to_response": "external_ids,watch/providers"]
                        )
                    } catch let error as ProviderError where error.kind == .notFound {
                        return (index, nil)
                    }
                    return (index, detail.show(hit, within: window))
                }
            }
            var shows: [(Int, OnAirShow)] = []
            for try await case let (index, show?) in group {
                shows.append((index, show))
            }
            return shows.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}

// MARK: - TMDB wire shapes for the guide

/// `tv/{id}` with external ids and watch providers, for the on-air guide only.
private struct OnAirDetail: Decodable {
    struct Network: Decodable {
        let name: String
        let logoPath: String?
    }

    struct NextEpisode: Decodable {
        let airDate: String?
        let seasonNumber: Int
        let episodeNumber: Int
        let name: String?
    }

    struct Region: Decodable {
        let link: String?
        let flatrate: [OnAirProvider]?
    }

    struct Providers: Decodable { let results: [String: Region]? }

    let networks: [Network]?
    let nextEpisodeToAir: NextEpisode?
    let externalIds: OnAirExternalIDs?
    let watchProviders: Providers?

    enum CodingKeys: String, CodingKey {
        case networks, nextEpisodeToAir, externalIds
        case watchProviders = "watch/providers"
    }

    func show(_ hit: CatalogHit, within window: ClosedRange<Date>) -> OnAirShow? {
        guard let next = nextEpisodeToAir, let airsAt = Date.catalogDay(next.airDate), window.contains(airsAt)
        else { return nil }
        var hit = hit
        hit.ids.imdb = hit.ids.imdb ?? externalIds?.imdbId?.nilIfBlank
        hit.ids.tvdb = hit.ids.tvdb ?? externalIds?.tvdbId.map(String.init)
        let channel = networks?.first.flatMap { network in
            network.name.nilIfBlank.map {
                OnAirChannel(name: $0, logoURL: network.logoPath.flatMap { URL(string: TMDBCatalog.logoBase + $0) })
            }
        }
        hit.network = channel?.name ?? hit.network
        var providers: [String: WatchProviders] = [:]
        for (code, region) in watchProviders?.results ?? [:] {
            let streaming = (region.flatrate ?? [])
                .sorted { ($0.displayPriority ?? .max) < ($1.displayPriority ?? .max) }
                .compactMap(\.provider)
            guard !streaming.isEmpty else { continue }
            providers[code.uppercased()] = WatchProviders(
                link: region.link.flatMap(URL.init(string:)), streaming: streaming
            )
        }
        return OnAirShow(
            hit: hit, channel: channel,
            next: OnAirEpisode(
                season: next.seasonNumber, number: next.episodeNumber, name: next.name?.nilIfBlank, airsAt: airsAt
            ),
            providers: providers
        )
    }
}

/// One streaming service in a region's `watch/providers` entry (JustWatch data).
private struct OnAirProvider: Decodable {
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?

    var provider: WatchProvider? {
        providerName.nilIfBlank.map {
            WatchProvider(name: $0, logoURL: logoPath.flatMap { URL(string: TMDBCatalog.logoBase + $0) })
        }
    }
}

private struct OnAirExternalIDs: Decodable {
    let imdbId: String?
    let tvdbId: Int?
}
