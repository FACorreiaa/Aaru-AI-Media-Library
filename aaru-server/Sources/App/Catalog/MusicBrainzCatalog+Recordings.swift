import Foundation

/// MUS-006 · one scrobbled track to identify: its spelling, plus any ids the scrobbler sent.
struct RecordingQuery: Sendable, Equatable {
    var artist: String
    var track: String
    var album: String?
    var recordingMBID: String?
    var isrc: String?
}

/// What MusicBrainz identified. A field is nil whenever the answer was not one exact thing.
struct RecordingMatch: Sendable, Equatable {
    var recordingMBID: String?
    var releaseGroupMBID: String?
    var artistMBID: String?

    static let none = RecordingMatch()
}

/// A provider that identifies a scrobbled track.
protocol RecordingMatching: Sendable {
    func match(_ query: RecordingQuery) async throws -> RecordingMatch
}

/// MUS-006: one recording search per track, through the catalog's own paced client so listens
/// and album search share MusicBrainz's one request a second. The search asks by the recording
/// id the scrobbler sent, else its ISRC, else the exact artist and title.
extension MusicBrainzCatalog: RecordingMatching {
    func match(_ query: RecordingQuery) async throws -> RecordingMatch {
        let lucene = if let mbid = query.recordingMBID {
            "rid:\(mbid)"
        } else if let isrc = query.isrc {
            "isrc:\(Self.luceneEscaped(isrc))"
        } else {
            "recording:\"\(Self.luceneEscaped(query.track))\" AND artist:\"\(Self.luceneEscaped(query.artist))\""
        }
        let page = try await get(RecordingSearchPage.self, "recording", ["query": lucene, "limit": "25"])
        return Self.match(query, in: page.recordings)
    }

    /// Nothing is guessed. A recording counts when it is the id the scrobbler sent, or when its
    /// title and artist are the listen's, compared case-, width- and space-folded, at a search
    /// score of 100. The album is the one whose title is the listen's album; with no album sent,
    /// it is the only album or EP the matching recordings appear on.
    static func match(_ query: RecordingQuery, in recordings: [MusicBrainzRecording]) -> RecordingMatch {
        let fold = Listen.fold
        let title = fold(query.track)
        let artist = fold(query.artist)
        let exact = recordings.filter { recording in
            if let mbid = query.recordingMBID, recording.id == mbid {
                return true
            }
            return recording.score == 100 && fold(recording.title) == title
                && (fold(recording.byline) == artist || fold(recording.artistCredit?.first?.name ?? "") == artist)
        }
        let album = query.album.map(fold)
        let groups = exact.flatMap { $0.releases ?? [] }.compactMap { release -> String? in
            guard let group = release.releaseGroup else { return nil }
            let fits = if let album {
                fold(group.title ?? "") == album || fold(release.title) == album
            } else {
                MusicBrainzCatalog.trackedTypes.contains(group.primaryType ?? "")
            }
            return fits ? group.id : nil
        }
        return RecordingMatch(
            recordingMBID: only(exact.map(\.id)),
            releaseGroupMBID: only(groups),
            artistMBID: only(exact.compactMap { $0.artistCredit?.first?.artist?.id })
        )
    }

    /// The value when every one is the same, else nil.
    private static func only(_ values: [String]) -> String? {
        let distinct = Set(values)
        return distinct.count == 1 ? distinct.first : nil
    }
}

// MARK: - MusicBrainz recording search (wire shapes)

private struct RecordingSearchPage: Decodable {
    let recordings: [MusicBrainzRecording]
}

struct MusicBrainzRecording: Decodable, Sendable {
    let id: String
    let score: Int?
    let title: String
    let artistCredit: [MusicBrainzCredit]?
    let releases: [MusicBrainzRelease]?

    enum CodingKeys: String, CodingKey {
        case id, score, title, releases
        case artistCredit = "artist-credit"
    }

    /// "Simon & Garfunkel": the credit as MusicBrainz joins it.
    var byline: String {
        (artistCredit ?? []).map { $0.name + ($0.joinphrase ?? "") }.joined()
    }
}

struct MusicBrainzCredit: Decodable, Sendable {
    struct Artist: Decodable, Sendable {
        let id: String
    }

    let name: String
    let joinphrase: String?
    let artist: Artist?
}

struct MusicBrainzRelease: Decodable, Sendable {
    let title: String
    let releaseGroup: MusicBrainzReleaseGroupRef?

    enum CodingKeys: String, CodingKey {
        case title
        case releaseGroup = "release-group"
    }
}

struct MusicBrainzReleaseGroupRef: Decodable, Sendable {
    let id: String
    let title: String?
    let primaryType: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case primaryType = "primary-type"
    }
}
