import AaruCore
import Foundation

/// Stremio's watched-episode field on a library item: `{anchorVideoId}:{anchorLength}:{bits}`,
/// where `bits` is base64 of a zlib stream, one bit per video, least significant bit first.
///
/// The bits follow the show's episode list as Stremio saw it when the field was written. The
/// anchor is a video id and how long the list was then, so the bits can be lined up with a list
/// that has since grown. Same rules as stremio-core's `WatchedBitField::construct_and_resize`.
enum StremioWatched {
    /// One entry in a show's episode list (Cinemeta `meta.videos`).
    struct Video: Equatable, Sendable {
        var id: String
        var season: Int
        var episode: Int
        var released: Date?
    }

    /// The episodes the field marks watched. Specials (season 0) are left out: their numbering
    /// differs between Cinemeta and TMDB, and a guess would tick the wrong episode.
    static func episodes(_ field: String, videos: [Video]) -> [EpisodeKey] {
        let ordered = ordered(videos)
        guard let flags = try? watched(field, videoIDs: ordered.map(\.id)) else { return [] }
        return zip(ordered, flags).compactMap { video, watched in
            guard watched, video.season > 0 else { return nil }
            return try? EpisodeKey(season: video.season, episode: video.episode)
        }
    }

    /// Stremio's order: season, then episode, then release date (an unknown date first).
    static func ordered(_ videos: [Video]) -> [Video] {
        videos.sorted { lhs, rhs in
            if lhs.season != rhs.season {
                return lhs.season < rhs.season
            }
            if lhs.episode != rhs.episode {
                return lhs.episode < rhs.episode
            }
            return (lhs.released ?? .distantPast) < (rhs.released ?? .distantPast)
        }
    }

    struct Malformed: Error, Equatable {}

    /// One flag per id in `videoIDs`. An anchor that is no longer in the list gives all false,
    /// as Stremio does.
    static func watched(_ field: String, videoIDs: [String]) throws -> [Bool] {
        // Video ids contain colons (`tt0903747:1:2`), so split from the right.
        var parts = field.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, let bits = parts.popLast(), let anchorLength = parts.popLast().flatMap({ Int($0) })
        else { throw Malformed() }
        let anchor = parts.joined(separator: ":")
        guard let data = Data(base64Encoded: bits) else { throw Malformed() }
        let bytes = try [UInt8](Zlib.inflate(data))
        guard let anchorIndex = videoIDs.firstIndex(of: anchor) else {
            return Array(repeating: false, count: videoIDs.count)
        }
        let offset = anchorLength - anchorIndex - 1
        return videoIDs.indices.map { index in
            let old = index + offset
            guard old >= 0, old / 8 < bytes.count else { return false }
            return (bytes[old / 8] >> (old % 8)) & 1 == 1
        }
    }
}
