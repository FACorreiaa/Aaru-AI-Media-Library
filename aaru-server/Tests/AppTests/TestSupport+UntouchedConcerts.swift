import AaruCore
import Foundation
@testable import aaru

extension UntouchedStore: ConcertStore {
    func place(userID _: UserID) async throws -> ConcertPlace? {
        throw Touched()
    }

    func savePlace(_: ConcertPlace, userID _: UserID, now _: Date) async throws {
        throw Touched()
    }

    func deletePlace(userID _: UserID) async throws {
        throw Touched()
    }

    func albumsMissingArtists(limit _: Int) async throws -> [AlbumArtistsDue] {
        throw Touched()
    }

    func saveAlbumArtists(_: [MusicArtist], titleID _: TitleID, now _: Date) async throws {
        throw Touched()
    }

    func artistsToMatch(checkedBefore _: Date, limit _: Int) async throws -> [MusicArtist] {
        throw Touched()
    }

    func saveMatch(musicbrainzID _: String, performerID _: String?, now _: Date) async throws {
        throw Touched()
    }

    func libraryArtists(userID _: UserID) async throws -> [LibraryArtist] {
        throw Touched()
    }
}
