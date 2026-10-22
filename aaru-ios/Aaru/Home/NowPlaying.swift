import AaruAPI
import AaruCore
import Foundation

typealias NowPlaying = Components.Schemas.NowPlaying

/// What a player is playing now (SCR-008, DESIGN.md §15), from `/v1/me/now-playing`. Players
/// report only when the state changes, so the position runs on from `updatedAt` while playing
/// and stands still while paused.
extension NowPlaying {
    /// The episode's length, nil when the player did not say.
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

    /// "Now playing · Stremio", "Paused · Disney+".
    var eyebrow: String {
        "\(state == .paused ? "Paused" : "Now playing") · \(sourceName)"
    }

    var sourceName: String {
        switch source {
        case .stremio: "Stremio"
        case .netflix: "Netflix"
        case .disneyPlus: "Disney+"
        case .primeVideo: "Prime Video"
        }
    }

    /// "S2 · E7 · Episode name"; nil for a film.
    var episodeLine: String? {
        episode.map { episode in
            [EpisodeCode.short(season: episode.season, number: episode.number), episodeName].compactMap(\.self).joined(separator: " · ")
        }
    }

    /// The "Now watching" Live Activity for this session, when it is an episode on the shelf: the
    /// same attributes the server's push-to-start sends, and a content state that puts the
    /// activity's clock where the player is.
    func liveActivity(now: Date, fallbackMinutes: Int) -> (NowWatchingAttributes, NowWatchingContent)? {
        guard let libraryItemId, let episode, let watchEventId = UUID(uuidString: watchEventId) else { return nil }
        let runtimeMinutes = duration.map { Int(($0 / 60).rounded(.up)) } ?? fallbackMinutes
        let position = position(at: now)
        let startedAt = now.addingTimeInterval(-position)
        let length = max(duration ?? TimeInterval(runtimeMinutes * 60), position)
        let attributes = NowWatchingAttributes(
            libraryItemId: libraryItemId, title: title.title, season: episode.season, episode: episode.number,
            episodeName: episodeName, posterURL: title.posterUrl, runtimeMinutes: runtimeMinutes,
            watchEventId: watchEventId
        )
        let content = NowWatchingContent(
            startedAt: startedAt, endsAt: startedAt.addingTimeInterval(length), showsEndTime: true, watched: false,
            pausedAt: state == .paused ? now : nil
        )
        return (attributes, content)
    }
}
