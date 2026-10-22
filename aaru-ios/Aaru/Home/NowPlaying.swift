import AaruAPI
import AaruCore
import Foundation

typealias NowPlaying = Components.Schemas.NowPlaying
typealias NowPlayingItem = Components.Schemas.NowPlayingItem
typealias NowPlayingReply = Components.Schemas.NowPlayingReply

/// What is playing now (SCR-008, SCR-009, DESIGN.md §15), from `/v1/me/now-playing`: library
/// episodes and movies, tracks and videos, in the Live Activity's order. Players report only
/// when the state changes, so the position runs on from `updatedAt` while playing and stands
/// still while paused.
extension NowPlayingItem {
    /// The length, nil when the player did not say.
    var duration: TimeInterval? {
        durationMs > 0 ? TimeInterval(durationMs) / 1000 : nil
    }

    /// Where the player is at `date`, never past the end.
    func position(at date: Date) -> TimeInterval {
        let reported = TimeInterval(positionMs) / 1000
        let live = state == .playing ? reported + max(0, date.timeIntervalSince(updatedAt)) : reported
        return duration.map { min(live, $0) } ?? live
    }

    /// 0…1, nil without a length.
    func fraction(at date: Date) -> Double? {
        duration.flatMap { $0 > 0 ? position(at: date) / $0 : nil }
    }

    func remaining(at date: Date) -> TimeInterval? {
        duration.map { max(0, $0 - position(at: date)) }
    }

    /// "Now playing · Stremio", "Paused · Disney+", "Listening · Spotify".
    var eyebrow: String {
        let verb = state == .paused ? "Paused" : kind == .track ? "Listening" : "Now playing"
        return "\(verb) · \(serviceName)"
    }

    /// The player as a person reads it; the source when the player gave no name.
    var serviceName: String {
        if let service, !service.isEmpty {
            return service
        }
        return switch source {
        case .stremio: "Stremio"
        case .netflix: "Netflix"
        case .disneyPlus: "Disney+"
        case .primeVideo: "Prime Video"
        case .listenbrainz: "ListenBrainz"
        case .youtube: "YouTube"
        }
    }

    /// The poster, cover or thumbnail.
    var artURL: String? {
        artworkUrl ?? title?.posterUrl
    }

    /// The Live Activity's row for this item, the same one the server pushes: its clock starts
    /// where the player would have started without a break, and a pause stands it still.
    var activityItem: NowPlayingActivityItem {
        let startedAt = updatedAt.addingTimeInterval(-TimeInterval(positionMs) / 1000)
        return NowPlayingActivityItem(
            id: id, kind: NowPlayingActivityItem.Kind(rawValue: kind.rawValue) ?? .video, title: name,
            subtitle: subtitle, service: serviceName, startedAt: startedAt,
            endsAt: duration.map { startedAt.addingTimeInterval($0) },
            pausedAt: state == .paused ? updatedAt : nil,
            libraryItemId: libraryItemId, season: episode?.season, episode: episode?.number, artworkURL: artURL
        )
    }
}

extension NowPlayingReply {
    /// `items`, or the one legacy `nowPlaying` from a server older than SCR-009.
    var playing: [NowPlayingItem] {
        if items.isEmpty, let nowPlaying {
            return [NowPlayingItem(nowPlaying)]
        }
        return items
    }
}

extension NowPlayingItem {
    /// A pre-SCR-009 session as an item: always a library episode or movie.
    init(_ playing: NowPlaying) {
        let source: SourcePayload = switch playing.source {
        case .stremio: .stremio
        case .netflix: .netflix
        case .disneyPlus: .disneyPlus
        case .primeVideo: .primeVideo
        }
        self.init(
            id: playing.watchEventId,
            kind: playing.episode == nil ? .movie : .episode,
            name: playing.title.title,
            subtitle: playing.episode.map { episode in
                [EpisodeCode.short(season: episode.season, number: episode.number), playing.episodeName]
                    .compactMap(\.self)
                    .joined(separator: " · ")
            },
            source: source,
            state: playing.state == .paused ? .paused : .playing,
            positionMs: playing.positionMs,
            durationMs: playing.durationMs,
            updatedAt: playing.updatedAt,
            artworkUrl: playing.title.posterUrl,
            libraryItemId: playing.libraryItemId,
            title: playing.title,
            episode: playing.episode
        )
    }
}
