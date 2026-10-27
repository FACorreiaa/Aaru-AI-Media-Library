import AaruCore
import Foundation

// MUS-005 · the listening log. Part of the data layer boundary in Stores.swift.

/// One play of a track as a scrobbler reported it, before it is stored.
struct NewListen: Sendable, Equatable {
    var listenedAt: Date
    var artist: String
    var track: String
    var album: String?
    var durationMs: Int?
    var isrc: String?
    var recordingMBID: String?
    var releaseMBID: String?
    var releaseGroupMBID: String?
    var artistMBID: String?
    var spotifyID: String?
    var originURL: String?
    /// The scrobbler ("Web Scrobbler") and the service it heard ("YouTube Music").
    var client: String?
    var musicService: String?

    var trackKey: String {
        Listen.trackKey(artist: artist, track: track)
    }

    /// Two listens of the same track this close together are one play sent twice, by one
    /// scrobbler retrying or by two scrobblers on the same play. Half the track, at most 90 s;
    /// 30 s when the length is unknown.
    var duplicateWindow: TimeInterval {
        durationMs.map { min(90, Double($0) / 2000) } ?? 30
    }
}

/// One stored listen.
struct Listen: Sendable, Equatable {
    var id: UUID
    var listenedAt: Date
    var artist: String
    var track: String
    var album: String?
    var durationMs: Int?
    var releaseGroupMBID: String?
    /// The album's title when it is in Aaru's catalog (MUS-006).
    var albumTitleID: UUID?
    var originURL: String?
    var client: String?
    var musicService: String?

    /// The artist and track, case-, width- and space-folded, joined by a unit separator: what
    /// makes two scrobblers' spellings of one play the same.
    static func trackKey(artist: String, track: String) -> String {
        fold(artist) + "\u{1F}" + fold(track)
    }

    /// Case-, width- and space-folded, so two spellings of one name compare equal.
    static func fold(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// MUS-008 · a period's listening, for Insights and the Recap.
struct ListenSummary: Sendable, Equatable {
    var listens: Int
    var durationMs: Int64
    /// The previous equal-length window; rolling spans only, as with the library's totals.
    var priorListens: Int?
    var priorDurationMs: Int64?
    var topArtist: ListenTotal?
    /// The top artist's three most played tracks.
    var topArtistTracks: [ListenTotal]
}

/// MUS-006 · one track no one has asked MusicBrainz about yet: its keys, and the newest listen's
/// spelling with any ids a scrobbler sent.
struct ListenLookup: Sendable, Equatable {
    var trackKey: String
    /// The album, lowercased; empty when the scrobbler sent none.
    var albumKey: String
    var query: RecordingQuery
}

/// What the top lists rank by.
enum ListenGrouping: String, Sendable {
    case artist, track, album
}

/// One row of a top list: an artist, a track (with its artist) or an album (with its artist).
struct ListenTotal: Sendable, Equatable {
    var artist: String
    var track: String?
    var album: String?
    var count: Int
    var durationMs: Int64
    /// The newest identified album among the row's listens: its cover, and its link once the
    /// album is in the catalog (MUS-008).
    var releaseGroupMBID: String?
    var albumTitleID: UUID?
}

/// A period's top list and the period's totals.
struct ListenTop: Sendable, Equatable {
    var period: StatsPeriod
    var listens: Int
    var durationMs: Int64
    var items: [ListenTotal]
}

protocol ListenStore: Sendable {
    /// Stores the listens in order, skipping any inside a stored listen's duplicate window.
    /// Returns how many were kept.
    func insert(_ listens: [NewListen], userID: UserID, agentTokenID: UUID?) async throws -> Int
    /// Newest first, older than `before` when it is set.
    func listens(userID: UserID, before: Date?, limit: Int) async throws -> [Listen]
    /// The period's totals and its `limit` most played artists, tracks or albums.
    /// `artist` narrows it to one artist, compared folded.
    func top(userID: UserID, by grouping: ListenGrouping, period: StatsPeriod, limit: Int, artist: String?)
        async throws -> ListenTop
    /// Tracks still waiting for an album that were never looked up, or whose last miss is older
    /// than `retryBefore`; newest listens first.
    func unresolved(retryBefore: Date, limit: Int) async throws -> [ListenLookup]
    /// Keeps what MusicBrainz said, and fills the ids of every listen of that track and album
    /// that lacks them. Returns how many listens gained an album.
    func resolve(_ lookup: ListenLookup, as match: RecordingMatch, at date: Date) async throws -> Int

    // MUS-004 · listening history imports. An import job's plays wait in staging until the user
    // applies them; applying keeps what the live duplicate window would keep.

    /// Adds plays to a job's staging, numbered from `index`.
    func stage(_ listens: [NewListen], jobID: ImportJobID, from index: Int) async throws
    /// Empties a job's staging, so a retried fetch starts over.
    func clearStaged(jobID: ImportJobID) async throws
    /// How many staged plays applying would keep: those outside every stored listen's duplicate
    /// window and outside the window of the play before them of the same track.
    func countNew(jobID: ImportJobID, userID: UserID) async throws -> Int
    /// Writes the plays `countNew` counts as the job's `import` listens, then empties its staging.
    /// Returns how many were written.
    func applyStaged(jobID: ImportJobID, userID: UserID) async throws -> Int
    /// Deletes the listens a job wrote. Returns how many.
    func deleteImported(jobID: ImportJobID, userID: UserID) async throws -> Int
    /// The newest listen an applied import of this source and account wrote, so the next import of
    /// it reads only what came after.
    func newestImported(userID: UserID, source: ImportSource, account: String) async throws -> Date?
}
