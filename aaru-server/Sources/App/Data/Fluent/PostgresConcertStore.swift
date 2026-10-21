import AaruCore
import FluentKit
import FluentSQL
import Foundation

struct PostgresConcertStore: ConcertStore {
    let database: any Database

    private var sql: any SQLDatabase {
        get throws { try sqlDatabase(database) }
    }

    func place(userID: UserID) async throws -> ConcertPlace? {
        struct Row: Decodable {
            let name: String
            let region: String?
            let country: String?
            let countryCode: String?
            let latitude: Double
            let longitude: Double
        }
        let row = try await sql.raw("""
        SELECT name, region, country, country_code, latitude, longitude FROM concert_places
        WHERE user_id = \(bind: userID.rawValue)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        guard let row, let point = GeoPoint(latitude: row.latitude, longitude: row.longitude) else { return nil }
        return ConcertPlace(
            name: row.name, region: row.region, country: row.country, countryCode: row.countryCode, point: point
        )
    }

    func savePlace(_ place: ConcertPlace, userID: UserID, now: Date) async throws {
        try await sql.raw("""
        INSERT INTO concert_places (user_id, name, region, country, country_code, latitude, longitude, updated_at)
        VALUES (\(bind: userID.rawValue), \(bind: place.name), \(bind: place.region), \(bind: place.country),
            \(bind: place.countryCode), \(bind: place.point.latitude), \(bind: place.point.longitude), \(bind: now))
        ON CONFLICT (user_id) DO UPDATE SET name = EXCLUDED.name, region = EXCLUDED.region,
            country = EXCLUDED.country, country_code = EXCLUDED.country_code, latitude = EXCLUDED.latitude,
            longitude = EXCLUDED.longitude, updated_at = EXCLUDED.updated_at
        """).run()
    }

    func deletePlace(userID: UserID) async throws {
        try await sql.raw("DELETE FROM concert_places WHERE user_id = \(bind: userID.rawValue)").run()
    }

    func albumsMissingArtists(limit: Int) async throws -> [AlbumArtistsDue] {
        struct Row: Decodable {
            let id: UUID
            let musicbrainz: String
        }
        return try await sql.raw("""
        SELECT t.id, t.musicbrainz FROM titles t
        WHERE t.type = 'album' AND t.musicbrainz IS NOT NULL AND t.artists_checked_at IS NULL
          AND EXISTS (SELECT 1 FROM library_items li WHERE li.title_id = t.id)
        ORDER BY t.id
        LIMIT \(bind: limit)
        """).all(decoding: Row.self).map { AlbumArtistsDue(titleID: TitleID($0.id), musicbrainzID: $0.musicbrainz) }
    }

    func saveAlbumArtists(_ artists: [MusicArtist], titleID: TitleID, now: Date) async throws {
        try await database.transaction { transaction in
            let sql = try sqlDatabase(transaction)
            for (position, artist) in artists.enumerated() {
                try await sql.raw("""
                INSERT INTO music_artists (musicbrainz, name)
                VALUES (\(bind: artist.musicbrainzID), \(bind: artist.name))
                ON CONFLICT (musicbrainz) DO UPDATE SET name = EXCLUDED.name
                """).run()
                try await sql.raw("""
                INSERT INTO album_artists (title_id, artist, position)
                VALUES (\(bind: titleID.rawValue), \(bind: artist.musicbrainzID), \(bind: position))
                ON CONFLICT (title_id, artist) DO UPDATE SET position = EXCLUDED.position
                """).run()
            }
            try await sql.raw("""
            UPDATE titles SET artists_checked_at = \(bind: now) WHERE id = \(bind: titleID.rawValue)
            """).run()
        }
    }

    func artistsToMatch(checkedBefore: Date, limit: Int) async throws -> [MusicArtist] {
        struct Row: Decodable {
            let musicbrainz: String
            let name: String
        }
        // Never-asked artists first, then the longest-unchecked.
        return try await sql.raw("""
        SELECT a.musicbrainz, a.name FROM music_artists a
        WHERE (a.matched_at IS NULL OR a.matched_at < \(bind: checkedBefore))
          AND EXISTS (
            SELECT 1 FROM album_artists aa JOIN library_items li ON li.title_id = aa.title_id
            WHERE aa.artist = a.musicbrainz
          )
        ORDER BY a.matched_at NULLS FIRST, a.musicbrainz
        LIMIT \(bind: limit)
        """).all(decoding: Row.self).map { MusicArtist(musicbrainzID: $0.musicbrainz, name: $0.name) }
    }

    func saveMatch(musicbrainzID: String, performerID: String?, now: Date) async throws {
        try await sql.raw("""
        UPDATE music_artists SET performer_id = \(bind: performerID), matched_at = \(bind: now)
        WHERE musicbrainz = \(bind: musicbrainzID)
        """).run()
    }

    func libraryArtists(userID: UserID) async throws -> [LibraryArtist] {
        struct Row: Decodable {
            let musicbrainz: String
            let name: String
            let performerId: String?
            let matchedAt: Date?
        }
        return try await sql.raw("""
        SELECT a.musicbrainz, a.name, a.performer_id, a.matched_at FROM music_artists a
        JOIN album_artists aa ON aa.artist = a.musicbrainz
        JOIN library_items li ON li.title_id = aa.title_id
        WHERE li.user_id = \(bind: userID.rawValue) AND li.status <> 'dropped'
        GROUP BY a.musicbrainz, a.name, a.performer_id, a.matched_at
        ORDER BY count(*) DESC, a.name
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            LibraryArtist(
                artist: MusicArtist(musicbrainzID: $0.musicbrainz, name: $0.name),
                performerID: $0.performerId, checked: $0.matchedAt != nil
            )
        }
    }
}
