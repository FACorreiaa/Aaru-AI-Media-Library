package concerts

import (
	"aaru-go-api/internal/provider"
	"context"
	"errors"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
)

// ErrNoPlace is neither a one-off position nor a saved "Concerts near" city: the client asks for one.
var ErrNoPlace = errors.New("no concert place")

// Service is MUS-003 · concerts near a place and for the artists in the user's library. Provider
// lists, the same for everyone at a place, linked out to buy; never a recommendation. Off (every
// answer unavailable) when no concert provider is configured (Listing nil).
type Service struct {
	Store   *Store
	Listing Listing
	Places  PlaceSearcher
	// Now defaults to time.Now.
	Now func() time.Time
	// ShareLookups is share links' own slice of the Ticketmaster day (SHR-002), so share
	// traffic never takes it all.
	ShareLookups *CallBudget

	cache          *Cache[Results]
	performerCache *Cache[[]Attraction]
	// eventCache is one concert by id for share links (SHR-002); a nil value means the provider
	// has no such event.
	eventCache *Cache[*Concert]
}

const (
	// ArtistsPerCall is performer ids per call: Ticketmaster takes many; 20 keeps the URL short.
	ArtistsPerCall = 20
	// MaxArtists is the most matched artists asked about per request, most-shelved first.
	MaxArtists = 60
	// MaxArtistConcerts is the most concerts "Your artists on tour" lists.
	MaxArtistConcerts = 50
	// MaxPerformers is the performers offered for one typed name.
	MaxPerformers = 8
	// ShareCallsPerDay is share links' daily slice of the Ticketmaster budget.
	ShareCallsPerDay = 1000
)

// Radii are the radii a client may ask for, in km.
var Radii = []int{25, 50, 100}

// NewService builds the service; listing nil turns concerts off, places nil finds no cities.
func NewService(store *Store, listing Listing, places PlaceSearcher) *Service {
	return &Service{
		Store: store, Listing: listing, Places: places, Now: time.Now, ShareLookups: NewCallBudget(ShareCallsPerDay),
		cache: NewCache[Results](), performerCache: NewCache[[]Attraction](), eventCache: NewCache[*Concert](),
	}
}

func (s *Service) now() time.Time {
	if s.Now == nil {
		return time.Now()
	}
	return s.Now()
}

// IsAvailable is whether a concert provider is configured.
func (s *Service) IsAvailable() bool { return s.Listing != nil }

// Nearby is one page of concerts near a place.
type Nearby struct {
	// Place is the saved city, when it was the centre.
	Place       *Place
	RadiusKm    int
	Page        int
	Results     Results
	Unavailable bool
}

// Searched is one page of concerts matching an artist (MUS-010).
type Searched struct {
	// Query is the name as searched, trimmed.
	Query string
	// PerformerID is the performer picked, when the search was by one.
	PerformerID *string
	Scope       Scope
	// Place is the saved city, when it was the centre or the distances are from it.
	Place *Place
	// RadiusKm is set for `near`.
	RadiusKm    *int
	Page        int
	Results     Results
	Unavailable bool
}

// ForArtists is "Your artists on tour".
type ForArtists struct {
	Concerts []Concert
	// Matched is library artists the provider knows.
	Matched int
	// Pending is library artists not looked up yet; they appear within the hour.
	Pending     int
	Unavailable bool
}

func emptyResults() Results { return Results{Concerts: []Concert{}} }

// Concert is one concert by provider id through the shared cache (SHR-002). Nil when concerts
// are off, the provider fails or is over budget with nothing cached, or the event is gone.
// Never fails.
func (s *Service) Concert(ctx context.Context, id string) *Concert {
	if s.Listing == nil {
		return nil
	}
	now := s.now()
	found, _ := s.eventCache.Value(ctx, "event:"+id, now, func(ctx context.Context) (*Concert, error) {
		if !s.ShareLookups.Take(now) {
			return nil, provider.NewError("ticketmaster", provider.KindUnavailable)
		}
		return s.Listing.Event(ctx, id)
	})
	return found
}

// Near is concerts around point (already rounded), or around the saved city when it is nil.
// ErrNoPlace when there is neither.
func (s *Service) Near(ctx context.Context, userID uuid.UUID, point *GeoPoint, radiusKm, page int) (Nearby, error) {
	if s.Listing == nil {
		return Nearby{RadiusKm: radiusKm, Page: page, Results: emptyResults(), Unavailable: true}, nil
	}
	var place *Place
	if point == nil {
		var err error
		if place, err = s.Store.Place(ctx, userID); err != nil {
			return Nearby{}, err
		}
	}
	center := point
	if center == nil && place != nil {
		center = &place.Point
	}
	if center == nil {
		return Nearby{}, ErrNoPlace
	}
	now := s.now()
	c := *center
	// The geohash cell, not the point, keys the cache: everyone in the same ~5 km cell shares it.
	key := "near:" + c.Geohash() + ":" + strconv.Itoa(radiusKm) + ":" + strconv.Itoa(page)
	results, ok := s.cache.Value(ctx, key, now, func(ctx context.Context) (Results, error) {
		return s.Listing.Near(ctx, c, radiusKm, page, now)
	})
	if !ok {
		results = emptyResults()
	}
	return Nearby{Place: place, RadiusKm: radiusKm, Page: page, Results: results, Unavailable: !ok}, nil
}

// Search is concerts matching an artist's name (MUS-010). `near` searches around point (already
// rounded) or the saved city; `anywhere` sends the provider the name alone and works out each
// venue's distance from the point or saved city here, after the shared cache.
func (s *Service) Search(ctx context.Context, search Search, userID uuid.UUID, point *GeoPoint) (Searched, error) {
	var radius *int
	if search.Scope == ScopeNear {
		r := search.RadiusKm
		radius = &r
	}
	out := Searched{Query: search.Query, PerformerID: search.PerformerID, Scope: search.Scope, RadiusKm: radius, Page: search.Page}
	if s.Listing == nil {
		out.Results, out.Unavailable = emptyResults(), true
		return out, nil
	}
	var place *Place
	if point == nil {
		var err error
		if place, err = s.Store.Place(ctx, userID); err != nil {
			return Searched{}, err
		}
	}
	center := point
	if center == nil && place != nil {
		center = &place.Point
	}
	var area *Area
	if search.Scope == ScopeNear {
		if center == nil {
			return Searched{}, ErrNoPlace
		}
		area = &Area{Point: *center, RadiusKm: search.RadiusKm}
	}
	now := s.now()
	// Keyed by the performer, or the name as everyone types it, and the cell; never by who asked.
	match := Match{Keyword: search.Query}
	matched := strings.ToLower(search.Query)
	if search.PerformerID != nil {
		match = Match{PerformerID: *search.PerformerID}
		matched = "performer=" + *search.PerformerID
	}
	cell, radiusKey := "*", "*"
	if area != nil {
		cell = area.Point.Geohash()
	}
	if radius != nil {
		radiusKey = strconv.Itoa(*radius)
	}
	key := "search:" + matched + ":" + cell + ":" + radiusKey + ":" + strconv.Itoa(search.Page)
	found, ok := s.cache.Value(ctx, key, now, func(ctx context.Context) (Results, error) {
		return s.Listing.Search(ctx, match, area, search.Page, now)
	})
	results := emptyResults()
	if ok {
		results = found
	}
	if search.Scope == ScopeAnywhere {
		concerts := make([]Concert, len(results.Concerts))
		for i, concert := range results.Concerts {
			concert.DistanceKm = nil
			if center != nil && concert.VenuePoint != nil {
				d := center.DistanceKm(*concert.VenuePoint)
				concert.DistanceKm = &d
			}
			concerts[i] = concert
		}
		results.Concerts = concerts
	}
	out.Place, out.Results, out.Unavailable = place, results, !ok
	return out, nil
}

// Performers is performers whose name matches what the user typed, for picking one before a
// search (MUS-010): the provider's own list, cached by the lowercased name. ok false when
// concerts are off or the provider did not answer.
func (s *Service) Performers(ctx context.Context, query string) (performers []Attraction, ok bool) {
	if s.Listing == nil {
		return nil, false
	}
	found, ok := s.performerCache.Value(ctx, "performers:"+strings.ToLower(query), s.now(), func(ctx context.Context) ([]Attraction, error) {
		return s.Listing.Attractions(ctx, query)
	})
	if !ok {
		return nil, false
	}
	seen := map[string]bool{}
	out := []Attraction{}
	for _, a := range found {
		if seen[a.ID] {
			continue
		}
		seen[a.ID] = true
		if len(out) < MaxPerformers {
			out = append(out, a)
		}
	}
	return out, true
}

// ForLibrary is upcoming concerts by the artists of the user's albums, matched by MusicBrainz id.
func (s *Service) ForLibrary(ctx context.Context, userID uuid.UUID) (ForArtists, error) {
	artists, err := s.Store.LibraryArtists(ctx, userID)
	if err != nil {
		return ForArtists{}, err
	}
	ids := []string{}
	pending := 0
	for _, a := range artists {
		if a.PerformerID != nil && !slices.Contains(ids, *a.PerformerID) {
			ids = append(ids, *a.PerformerID)
		}
		if !a.Checked {
			pending++
		}
	}
	if s.Listing == nil {
		return ForArtists{Concerts: []Concert{}, Unavailable: true}, nil
	}
	now := s.now()
	var chunks [][]string
	for start := 0; start < min(len(ids), MaxArtists); start += ArtistsPerCall {
		chunk := slices.Clone(ids[start:min(start+ArtistsPerCall, len(ids), MaxArtists)])
		sort.Strings(chunk)
		chunks = append(chunks, chunk)
	}
	concerts := []Concert{}
	failed := 0
	for _, chunk := range chunks {
		found, ok := s.cache.Value(ctx, "artists:"+strings.Join(chunk, ","), now, func(ctx context.Context) (Results, error) {
			list, err := s.Listing.Performing(ctx, chunk, now)
			return Results{Concerts: list}, err
		})
		if !ok {
			failed++
			continue
		}
		for _, concert := range found.Concerts {
			if !slices.ContainsFunc(concerts, func(c Concert) bool { return c.ID == concert.ID }) {
				concerts = append(concerts, concert)
			}
		}
	}
	timeOf := func(c Concert) string {
		if c.LocalTime == nil {
			return ""
		}
		return *c.LocalTime
	}
	sort.SliceStable(concerts, func(a, b int) bool {
		if concerts[a].LocalDate != concerts[b].LocalDate {
			return concerts[a].LocalDate < concerts[b].LocalDate
		}
		return timeOf(concerts[a]) < timeOf(concerts[b])
	})
	if len(concerts) > MaxArtistConcerts {
		concerts = concerts[:MaxArtistConcerts]
	}
	return ForArtists{
		Concerts: concerts, Matched: len(ids), Pending: pending,
		Unavailable: len(chunks) > 0 && failed == len(chunks),
	}, nil
}

// SearchPlaces is cities matching what the user typed, for the "Concerts near" picker.
func (s *Service) SearchPlaces(ctx context.Context, query string) ([]Place, error) {
	if s.Places == nil {
		return []Place{}, nil
	}
	return s.Places.Places(ctx, query)
}
