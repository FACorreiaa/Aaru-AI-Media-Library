import Foundation
import Logging
import ServiceLifecycle

/// MUS-003 · keeps "Your artists on tour" answerable without asking per request. Each pass
/// looks up the artists of albums nobody has looked up (MusicBrainz), then asks the concert
/// provider about artists never matched or matched over a month ago. An artist matches only
/// when the provider's performer carries the same MusicBrainz id; a name alone never does.
struct ConcertRefresher: Sendable {
    /// MusicBrainz allows one call a second, shared with search.
    var albumLimit = 30
    /// Each artist costs one provider call; 20 a pass every half hour stays far inside the budget.
    var artistLimit = 20
    static let rematchAfter: TimeInterval = 30 * 24 * 60 * 60
    /// MusicBrainz's "Various Artists": credited on compilations, never on a stage.
    static let variousArtists = "89ad4ac3-39f7-470e-963a-56509c546377"

    let stores: Stores
    let artists: (any AlbumArtistListing)?
    let listing: (any ConcertListing)?
    var now: @Sendable () -> Date = { Date() }

    /// Returns how many albums were looked up. A provider failure ends the pass; the rest wait.
    func fillAlbumArtists() async throws -> Int {
        guard let artists else { return 0 }
        let now = now()
        var done = 0
        for album in try await stores.concerts.albumsMissingArtists(limit: albumLimit) {
            try Task.checkCancellation()
            let found: [MusicArtist]?
            do {
                found = try await artists.artists(releaseGroup: album.musicbrainzID)
            } catch is ProviderError {
                break
            }
            try await stores.concerts.saveAlbumArtists(found ?? [], titleID: album.titleID, now: now)
            done += 1
        }
        return done
    }

    /// Returns how many artists were matched or found unknown. Stops when the provider fails or
    /// the day's call budget is spent.
    func matchArtists() async throws -> Int {
        guard let listing else { return 0 }
        let now = now()
        let due = try await stores.concerts.artistsToMatch(
            checkedBefore: now.addingTimeInterval(-Self.rematchAfter), limit: artistLimit
        )
        var done = 0
        for artist in due {
            try Task.checkCancellation()
            var match: String?
            if artist.musicbrainzID != Self.variousArtists {
                do {
                    match = try await listing.attractions(named: artist.name)
                        .first { $0.musicbrainzIDs.contains(artist.musicbrainzID) }?.id
                } catch is ProviderError {
                    break
                }
            }
            try await stores.concerts.saveMatch(musicbrainzID: artist.musicbrainzID, performerID: match, now: now)
            done += 1
        }
        return done
    }
}

/// Runs the concert refresher every half hour in the API process.
struct ConcertRefreshService: Service {
    let refresher: ConcertRefresher
    let logger: Logger
    var interval: Duration = .seconds(1800)

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                do {
                    let albums = try await refresher.fillAlbumArtists()
                    let artists = try await refresher.matchArtists()
                    if albums + artists > 0 {
                        logger.info(
                            "Concert artists refreshed",
                            metadata: ["albums": "\(albums)", "artists": "\(artists)"]
                        )
                    }
                } catch is CancellationError {
                    return
                } catch {
                    logger.error("Concert artist pass failed", metadata: ["error": "\(error)"])
                }
                try? await Task.sleep(for: interval)
            }
        }
    }
}
