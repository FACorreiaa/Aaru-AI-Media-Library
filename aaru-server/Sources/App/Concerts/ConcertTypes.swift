import AaruCore
import Foundation

/// MUS-003 · one music event as the concert provider lists it. Catalog data, linked out: Aaru
/// sells nothing and keeps nothing past the cache.
struct Concert: Sendable, Equatable {
    var id: String
    var name: String
    /// The acts on the bill, headliner first.
    var artists: [String]
    /// The exact start, when the provider knows it.
    var startsAt: Date?
    /// The day at the venue, `YYYY-MM-DD`.
    var localDate: String
    /// The time at the venue, `HH:mm`, when announced.
    var localTime: String?
    var venue: String?
    var city: String?
    var country: String?
    /// From the searched point; nil for an artist's concerts.
    var distanceKm: Double?
    /// The provider's event page, where tickets are sold.
    var url: URL
    var imageURL: URL?
    /// The venue's position, rounded, when the provider gives one. Only to work out a distance on
    /// the server (MUS-010); never sent to a client.
    var venuePoint: GeoPoint?
}

/// Where a search by artist looks (MUS-010).
enum ConcertSearchScope: String, Sendable, Equatable {
    /// Around a point or the saved city, inside a radius.
    case near
    /// Every upcoming date; no area is sent to the provider.
    case anywhere
}

/// One search by artist (MUS-010): the name as typed, trimmed, and where to look.
struct ConcertSearch: Sendable, Equatable {
    var query: String
    var scope: ConcertSearchScope
    /// Used by `near` only.
    var radiusKm: Int
    var page: Int
}

/// One page of concerts.
struct ConcertResults: Sendable, Equatable {
    var concerts: [Concert]
    var hasMore: Bool
}

/// A position to search around, rounded to two decimals (about a kilometre) before it is used,
/// stored or cached. Never logged.
struct GeoPoint: Sendable, Equatable {
    var latitude: Double
    var longitude: Double

    init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite, (-90 ... 90).contains(latitude),
              (-180 ... 180).contains(longitude)
        else { return nil }
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
    }

    /// Great-circle distance in kilometres (haversine, mean Earth radius).
    func distanceKm(to other: GeoPoint) -> Double {
        let radians = Double.pi / 180
        let dLat = (other.latitude - latitude) * radians
        let dLon = (other.longitude - longitude) * radians
        let half = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * radians) * cos(other.latitude * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6371.0088 * 2 * atan2(half.squareRoot(), (1 - half).squareRoot())
    }

    /// The geohash cell holding this point. Precision 5 is a cell of about 5 × 5 km, which is
    /// what the concert provider is sent and what the cache is keyed by.
    func geohash(precision: Int = 5) -> String {
        let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var bits = 0
        var value = 0
        var even = true
        while hash.count < precision {
            if even {
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude >= mid {
                    value = value << 1 | 1
                    lonRange.0 = mid
                } else {
                    value <<= 1
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if latitude >= mid {
                    value = value << 1 | 1
                    latRange.0 = mid
                } else {
                    value <<= 1
                    latRange.1 = mid
                }
            }
            even.toggle()
            bits += 1
            if bits == 5 {
                hash.append(alphabet[value])
                bits = 0
                value = 0
            }
        }
        return hash
    }
}

/// A named place: the user's saved "Concerts near" city, or a geocoder's answer.
struct ConcertPlace: Sendable, Equatable {
    var name: String
    var region: String?
    var country: String?
    var countryCode: String?
    var point: GeoPoint
}

/// A music artist by MusicBrainz id, as an album credits them.
struct MusicArtist: Sendable, Equatable {
    var musicbrainzID: String
    var name: String
}

/// An artist from the user's library, and the concert provider's id for them once matched.
struct LibraryArtist: Sendable, Equatable {
    var artist: MusicArtist
    var performerID: String?
    /// Whether the provider has been asked about this artist yet.
    var checked: Bool
}

/// An album still waiting for its artists.
struct AlbumArtistsDue: Sendable, Equatable {
    var titleID: TitleID
    var musicbrainzID: String
}

/// A performer as the concert provider lists them, with the MusicBrainz ids it links.
struct ConcertAttraction: Sendable, Equatable {
    var id: String
    var name: String
    var musicbrainzIDs: [String]
}

/// Concerts from a provider (Ticketmaster today). Named for the job, not the vendor.
protocol ConcertListing: Sendable {
    /// Music events around a point, soonest first. `page` is 1-based.
    func near(_ point: GeoPoint, radiusKm: Int, page: Int, from: Date) async throws -> ConcertResults
    /// Music events matching `keyword` as free text, soonest first: around `near` (a point and a
    /// radius in km) when given, else anywhere. `page` is 1-based (MUS-010).
    func search(_ keyword: String, near: (point: GeoPoint, radiusKm: Int)?, page: Int, from: Date) async throws
        -> ConcertResults
    /// Upcoming events for these provider performer ids, soonest first.
    func performing(_ attractionIDs: [String], from: Date) async throws -> [Concert]
    /// Performers whose name matches, with their MusicBrainz links.
    func attractions(named name: String) async throws -> [ConcertAttraction]
}

/// Turns a typed city into places (Open-Meteo today).
protocol PlaceSearching: Sendable {
    func places(matching query: String) async throws -> [ConcertPlace]
}

/// An album's credited artists by MusicBrainz id (MusicBrainz).
protocol AlbumArtistListing: Sendable {
    /// Nil when the provider does not know the release group.
    func artists(releaseGroup mbid: String) async throws -> [MusicArtist]?
}

protocol ConcertStore: Sendable {
    func place(userID: UserID) async throws -> ConcertPlace?
    func savePlace(_ place: ConcertPlace, userID: UserID, now: Date) async throws
    func deletePlace(userID: UserID) async throws
    /// Albums in someone's library whose artists have not been looked up.
    func albumsMissingArtists(limit: Int) async throws -> [AlbumArtistsDue]
    /// Saves the album's artists and stamps it as looked up, even when the list is empty.
    func saveAlbumArtists(_ artists: [MusicArtist], titleID: TitleID, now: Date) async throws
    /// Artists of albums in someone's library that were never matched, or matched before `checkedBefore`.
    func artistsToMatch(checkedBefore: Date, limit: Int) async throws -> [MusicArtist]
    func saveMatch(musicbrainzID: String, performerID: String?, now: Date) async throws
    /// The artists of the user's albums, dropped ones aside, most-shelved first.
    func libraryArtists(userID: UserID) async throws -> [LibraryArtist]
}
