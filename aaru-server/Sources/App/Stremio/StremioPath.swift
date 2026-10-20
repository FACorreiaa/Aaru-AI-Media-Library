import AaruCore
import Foundation

/// One request to the Stremio addon, parsed from its path (SCR-003). The protocol fixes the
/// shapes: `/stremio/{token}/manifest.json`, `/stremio/{token}/{resource}/{type}/{id}.json` and
/// `/stremio/{token}/{resource}/{type}/{id}/{extra}.json`, where `extra` is `a=b&c=d`.
struct StremioRequest: Sendable, Equatable {
    enum Route: Sendable, Equatable {
        case manifest
        case configure
        case resource(name: String, type: String, id: String, extra: [String: String])
    }

    var token: String
    var route: Route

    init?(path: String) {
        guard path.hasPrefix("/stremio/") else { return nil }
        let segments = path.dropFirst("/stremio/".count).split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard let token = segments.first, !token.isEmpty else { return nil }
        self.token = token
        let rest = Array(segments.dropFirst())
        switch rest.count {
        case 0:
            route = .configure
        case 1 where rest[0] == "manifest.json":
            route = .manifest
        case 1 where rest[0] == "configure" || rest[0].isEmpty:
            route = .configure
        case 3, 4:
            guard let last = rest.last, last.hasSuffix(".json") else { return nil }
            let trimmed = String(last.dropLast(".json".count))
            let id = rest.count == 3 ? trimmed : rest[2]
            guard let decodedID = id.removingPercentEncoding, !decodedID.isEmpty else { return nil }
            route = .resource(
                name: rest[0], type: rest[1], id: decodedID,
                extra: rest.count == 4 ? Self.extra(trimmed) : [:]
            )
        default:
            return nil
        }
    }

    /// `action=stop&currentTime=1200&videoId=tt1%3A1%3A2` → keys and decoded values. A segment
    /// that arrives encoded whole (`action%3Dstop%26…`) is decoded once first.
    static func extra(_ segment: String) -> [String: String] {
        var raw = segment
        if !raw.contains("="), let decoded = raw.removingPercentEncoding, decoded.contains("=") {
            raw = decoded
        }
        var values: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let key = parts[0].removingPercentEncoding,
                  let value = parts[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding
            else { continue }
            values[key] = value
        }
        return values
    }
}

/// A Stremio content id: an IMDb id (what Cinemeta and stream addons use) or Aaru's own
/// `aaru:{titleId}` for titles without one; either with `:season:episode` for an episode.
struct StremioID: Sendable, Equatable {
    enum Base: Sendable, Equatable {
        case imdb(String)
        case aaru(TitleID)
    }

    var base: Base
    var episode: EpisodeKey?

    init(base: Base, episode: EpisodeKey? = nil) {
        self.base = base
        self.episode = episode
    }

    init?(_ raw: String) {
        var parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.first == "aaru" {
            guard parts.count >= 2, let uuid = UUID(uuidString: parts[1]) else { return nil }
            base = .aaru(TitleID(uuid))
            parts.removeFirst(2)
        } else if let first = parts.first, first.hasPrefix("tt"), first.count > 2,
                  first.dropFirst(2).allSatisfy(\.isNumber)
        {
            base = .imdb(first)
            parts.removeFirst()
        } else {
            return nil
        }
        switch parts.count {
        case 0:
            episode = nil
        case 2:
            guard let season = Int(parts[0]), let number = Int(parts[1]),
                  let key = try? EpisodeKey(season: season, episode: number)
            else { return nil }
            episode = key
        default:
            return nil
        }
    }

    /// The id Stremio should see for a title: its IMDb id when known, so Cinemeta supplies the
    /// details and stream addons recognise it; otherwise Aaru's own.
    static func forTitle(_ title: Title) -> String {
        title.ids.imdb ?? "aaru:\(title.id.rawValue.uuidString.lowercased())"
    }

    var mediaRef: (titleID: TitleID?, ids: ExternalIDs) {
        switch base {
        case let .imdb(imdb): (nil, ExternalIDs(imdb: imdb))
        case let .aaru(id): (id, ExternalIDs())
        }
    }
}
