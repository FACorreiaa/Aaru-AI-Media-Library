// Package concerts is MUS-003 and MUS-010 (Sources/App/Concerts): concerts near a place, by an
// artist's name or picked performer, and by the artists of the user's albums, matched by
// MusicBrainz id. Catalog data from Ticketmaster, linked out to buy; Aaru sells nothing and keeps
// nothing past the cache. A position is rounded to two decimals before it is used and never
// stored; the saved "Concerts near" city is the only place kept.
package concerts

import (
	"context"
	"math"
	"time"

	"github.com/google/uuid"
)

// Concert is one music event as the concert provider lists it.
type Concert struct {
	ID   string
	Name string
	// Artists are the acts on the bill, headliner first.
	Artists []string
	// StartsAt is the exact start, when the provider knows it.
	StartsAt *time.Time
	// LocalDate is the day at the venue, `YYYY-MM-DD`.
	LocalDate string
	// LocalTime is the time at the venue, `HH:mm`, when announced.
	LocalTime *string
	Venue     *string
	City      *string
	Country   *string
	// DistanceKm is from the searched point; nil for an artist's concerts.
	DistanceKm *float64
	// URL is the provider's event page, where tickets are sold.
	URL      string
	ImageURL *string
	// VenuePoint is the venue's position, rounded, when the provider gives one. Only to work out
	// a distance on the server (MUS-010); never sent to a client.
	VenuePoint *GeoPoint
}

// Scope is where a search by artist looks (MUS-010).
type Scope string

const (
	// ScopeNear is around a point or the saved city, inside a radius.
	ScopeNear Scope = "near"
	// ScopeAnywhere is every upcoming date; no area is sent to the provider.
	ScopeAnywhere Scope = "anywhere"
)

// Match is what a search by artist matches (MUS-010): the provider's free text, or one
// performer the user picked from the provider's own list (PerformerID set).
type Match struct {
	Keyword     string
	PerformerID string
}

// Area is a point and a radius in km to search around.
type Area struct {
	Point    GeoPoint
	RadiusKm int
}

// Search is one search by artist (MUS-010): the name as typed, trimmed, and where to look.
type Search struct {
	Query string
	// PerformerID is the provider's id of a performer picked from the list; nil searches the
	// name as free text.
	PerformerID *string
	Scope       Scope
	// RadiusKm is used by `near` only.
	RadiusKm int
	Page     int
}

// Results is one page of concerts.
type Results struct {
	Concerts []Concert
	HasMore  bool
}

// GeoPoint is a position to search around, rounded to two decimals (about a kilometre) before it
// is used, stored or cached. Never logged.
type GeoPoint struct {
	Latitude  float64
	Longitude float64
}

// NewGeoPoint rounds the position; false when it is not a position on Earth.
func NewGeoPoint(latitude, longitude float64) (GeoPoint, bool) {
	if math.IsNaN(latitude) || math.IsInf(latitude, 0) || math.IsNaN(longitude) || math.IsInf(longitude, 0) ||
		latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 {
		return GeoPoint{}, false
	}
	return GeoPoint{Latitude: math.Round(latitude*100) / 100, Longitude: math.Round(longitude*100) / 100}, true
}

// DistanceKm is the great-circle distance in kilometres (haversine, mean Earth radius).
func (p GeoPoint) DistanceKm(other GeoPoint) float64 {
	radians := math.Pi / 180
	dLat := (other.Latitude - p.Latitude) * radians
	dLon := (other.Longitude - p.Longitude) * radians
	half := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(p.Latitude*radians)*math.Cos(other.Latitude*radians)*math.Sin(dLon/2)*math.Sin(dLon/2)
	return 6371.0088 * 2 * math.Atan2(math.Sqrt(half), math.Sqrt(1-half))
}

const geohashAlphabet = "0123456789bcdefghjkmnpqrstuvwxyz"

// Geohash is the geohash cell holding this point, at precision 5: a cell of about 5 × 5 km,
// which is what the concert provider is sent and what the cache is keyed by.
func (p GeoPoint) Geohash() string { return p.GeohashPrecision(5) }

// GeohashPrecision is the geohash cell at the given precision.
func (p GeoPoint) GeohashPrecision(precision int) string {
	latRange := [2]float64{-90, 90}
	lonRange := [2]float64{-180, 180}
	hash := make([]byte, 0, precision)
	bits, value, even := 0, 0, true
	for len(hash) < precision {
		if even {
			mid := (lonRange[0] + lonRange[1]) / 2
			if p.Longitude >= mid {
				value = value<<1 | 1
				lonRange[0] = mid
			} else {
				value <<= 1
				lonRange[1] = mid
			}
		} else {
			mid := (latRange[0] + latRange[1]) / 2
			if p.Latitude >= mid {
				value = value<<1 | 1
				latRange[0] = mid
			} else {
				value <<= 1
				latRange[1] = mid
			}
		}
		even = !even
		bits++
		if bits == 5 {
			hash = append(hash, geohashAlphabet[value])
			bits, value = 0, 0
		}
	}
	return string(hash)
}

// Place is a named place: the user's saved "Concerts near" city, or a geocoder's answer.
type Place struct {
	Name        string
	Region      *string
	Country     *string
	CountryCode *string
	Point       GeoPoint
}

// MusicArtist is a music artist by MusicBrainz id, as an album credits them.
type MusicArtist struct {
	MusicBrainzID string
	Name          string
}

// LibraryArtist is an artist from the user's library, and the concert provider's id for them
// once matched.
type LibraryArtist struct {
	Artist      MusicArtist
	PerformerID *string
	// Checked is whether the provider has been asked about this artist yet.
	Checked bool
}

// AlbumArtistsDue is an album still waiting for its artists.
type AlbumArtistsDue struct {
	TitleID       uuid.UUID
	MusicBrainzID string
}

// Attraction is a performer as the concert provider lists them, with the MusicBrainz ids it links.
type Attraction struct {
	ID             string
	Name           string
	MusicBrainzIDs []string
	// ImageURL is the provider's picture of the performer, referenced, never hosted.
	ImageURL *string
}

// Listing is concerts from a provider (Ticketmaster today). Named for the job, not the vendor.
type Listing interface {
	// Near is music events around a point, soonest first. page is 1-based.
	Near(ctx context.Context, point GeoPoint, radiusKm, page int, from time.Time) (Results, error)
	// Search is music events matching a name as free text or by one performer, soonest first:
	// around near when given, else anywhere. page is 1-based (MUS-010).
	Search(ctx context.Context, match Match, near *Area, page int, from time.Time) (Results, error)
	// Performing is upcoming events for these provider performer ids, soonest first.
	Performing(ctx context.Context, attractionIDs []string, from time.Time) ([]Concert, error)
	// Attractions is performers whose name matches, with their MusicBrainz links.
	Attractions(ctx context.Context, name string) ([]Attraction, error)
	// Event is one event by provider id; nil when the provider has no such event (SHR-002).
	Event(ctx context.Context, id string) (*Concert, error)
}

// PlaceSearcher turns a typed city into places (Open-Meteo today).
type PlaceSearcher interface {
	Places(ctx context.Context, query string) ([]Place, error)
}

// ArtistSource is an album's credited artists by MusicBrainz id (Swift's AlbumArtistListing,
// implemented by the MusicBrainz catalog).
type ArtistSource interface {
	// AlbumArtists is nil, without an error, when the provider does not know the release group.
	AlbumArtists(ctx context.Context, releaseGroupMBID string) ([]MusicArtist, error)
}
