import AaruAPI
import Foundation

/// For previews: albums with their tracklists (MUS-001). No artwork, so previews check the
/// square fallback.
enum AlbumSample {
    static let okComputerTracks: [AlbumTrack] = [
        ("Airbag", 284), ("Paranoid Android", 383), ("Subterranean Homesick Alien", 267),
        ("Exit Music (For a Film)", 264), ("Let Down", 299), ("Karma Police", 261), ("Fitter Happier", 117),
        ("Electioneering", 230), ("Climbing Up the Walls", 285), ("No Surprises", 228), ("Lucky", 259),
        ("The Tourist", 324),
    ].enumerated().map { offset, track in
        AlbumTrack(disc: 1, position: offset + 1, name: track.0, lengthMs: track.1 * 1000)
    }

    /// Two discs, so the tracklist groups into "Disc 1" and "Disc 2".
    static let fragileTracks: [AlbumTrack] = [
        AlbumTrack(disc: 1, position: 1, name: "Somewhat Damaged", lengthMs: 271_000),
        AlbumTrack(disc: 1, position: 2, name: "The Day the World Went Away", lengthMs: 273_000),
        AlbumTrack(disc: 1, position: 3, name: "The Frail", lengthMs: 114_000),
        AlbumTrack(disc: 1, position: 4, name: "The Wretched", lengthMs: 325_000),
        AlbumTrack(disc: 2, position: 1, name: "The Way Out Is Through", lengthMs: 257_000),
        AlbumTrack(disc: 2, position: 2, name: "Into the Void", lengthMs: 289_000),
        AlbumTrack(disc: 2, position: 3, name: "Where Is Everybody?", lengthMs: nil),
    ]

    static func entry(
        _ title: String, artist: String, year: Int, status: LibraryStatus = .inProgress
    ) -> LibraryEntry {
        LibraryEntry(
            id: UUID().uuidString,
            title: .init(
                id: UUID().uuidString, _type: .album, title: title, year: year, byline: artist, isAnime: false,
                ids: .init(musicbrainz: UUID().uuidString)
            ),
            status: status,
            rating: 10,
            isOwned: true,
            addedAt: .now,
            updatedAt: .now,
            inBacklog: false
        )
    }

    static func detail(for entry: LibraryEntry, genres: [String], tracks: [AlbumTrack]?) -> TitleDetail {
        TitleDetail(
            id: entry.title.id, _type: .album, title: entry.title.title, year: entry.title.year, isAnime: false,
            ids: entry.title.ids, byline: entry.title.byline, genres: genres, tracks: tracks
        )
    }
}
