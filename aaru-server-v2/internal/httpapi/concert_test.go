package httpapi

import (
	"aaru-go-api/internal/concerts"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/provider"
	"context"
	"fmt"
	"net/http"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// fakeConcerts is a concert provider that records what it was asked. Test-only.
type fakeConcerts struct {
	mu               sync.Mutex
	failing          bool
	nearCalls        []concerts.GeoPoint
	nearRadii        []int
	searchCalls      []concerts.Match
	searchAreas      []*concerts.Area
	performingCalls  [][]string
	attractionCalls  []string
	eventCalls       []string
	nearConcerts     []concerts.Concert
	searchConcerts   []concerts.Concert
	byAttraction     map[string][]concerts.Concert
	attractionsBy    map[string][]concerts.Attraction
	artistsByAlbum   map[string][]concerts.MusicArtist
	eventsByID       map[string]concerts.Concert
}

func newFakeConcerts() *fakeConcerts {
	return &fakeConcerts{
		byAttraction: map[string][]concerts.Concert{}, attractionsBy: map[string][]concerts.Attraction{},
		artistsByAlbum: map[string][]concerts.MusicArtist{}, eventsByID: map[string]concerts.Concert{},
	}
}

func (f *fakeConcerts) fail(v bool) { f.mu.Lock(); f.failing = v; f.mu.Unlock() }

func (f *fakeConcerts) check() error {
	if f.failing {
		return provider.NewError("ticketmaster", provider.KindUnavailable)
	}
	return nil
}

func (f *fakeConcerts) Near(_ context.Context, point concerts.GeoPoint, radiusKm, _ int, _ time.Time) (concerts.Results, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.nearCalls = append(f.nearCalls, point)
	f.nearRadii = append(f.nearRadii, radiusKm)
	return concerts.Results{Concerts: f.nearConcerts}, f.check()
}

func (f *fakeConcerts) Search(_ context.Context, match concerts.Match, near *concerts.Area, _ int, _ time.Time) (concerts.Results, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.searchCalls = append(f.searchCalls, match)
	f.searchAreas = append(f.searchAreas, near)
	return concerts.Results{Concerts: slices.Clone(f.searchConcerts)}, f.check()
}

func (f *fakeConcerts) Performing(_ context.Context, ids []string, _ time.Time) ([]concerts.Concert, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.performingCalls = append(f.performingCalls, ids)
	var out []concerts.Concert
	for _, id := range ids {
		out = append(out, f.byAttraction[id]...)
	}
	return out, f.check()
}

func (f *fakeConcerts) Attractions(_ context.Context, name string) ([]concerts.Attraction, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.attractionCalls = append(f.attractionCalls, name)
	return f.attractionsBy[name], f.check()
}

func (f *fakeConcerts) Event(_ context.Context, id string) (*concerts.Concert, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.eventCalls = append(f.eventCalls, id)
	if err := f.check(); err != nil {
		return nil, err
	}
	if c, ok := f.eventsByID[id]; ok {
		return &c, nil
	}
	return nil, nil
}

func (f *fakeConcerts) AlbumArtists(_ context.Context, mbid string) ([]concerts.MusicArtist, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.artistsByAlbum[mbid], nil
}

func (f *fakeConcerts) lastNear() concerts.GeoPoint {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.nearCalls[len(f.nearCalls)-1]
}

func sampleConcert(id, day string, at *string) concerts.Concert {
	venue, city, country, distance := "Coliseu", "Lisboa", "Portugal", 1.234
	return concerts.Concert{
		ID: id, Name: "Show " + id, Artists: []string{"Band " + id}, LocalDate: day, LocalTime: at,
		Venue: &venue, City: &city, Country: &country, DistanceKm: &distance, URL: "file:///event/" + id,
	}
}

func withConcerts(fake *fakeConcerts) func(*Deps) {
	return func(d *Deps) {
		d.Concerts = concerts.NewService(&concerts.Store{Q: sqlc.New(d.Pool), Pool: d.Pool}, fake, nil)
	}
}

func TestConcertsOffWithoutAProvider(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	setting := decode[map[string]any](t, h.do(http.MethodGet, "/v1/me/concert-place", bearer, nil))
	assert.Equal(t, false, setting["available"])
	near := decode[map[string]any](t, h.do(http.MethodPost, "/v1/concerts/near", bearer, map[string]any{"radiusKm": 50}))
	assert.Equal(t, true, near["unavailable"])
	artists := decode[map[string]any](t, h.do(http.MethodGet, "/v1/concerts/artists", bearer, nil))
	assert.Equal(t, true, artists["unavailable"])
	search := decode[map[string]any](t, h.do(http.MethodPost, "/v1/concerts/search", bearer, map[string]any{
		"q": "Radiohead", "scope": "anywhere", "radiusKm": 50,
	}))
	assert.Equal(t, true, search["unavailable"])
	off := decode[map[string]any](t, h.do(http.MethodPost, "/v1/concerts/performers", bearer, map[string]any{"q": "Radiohead"}))
	assert.Equal(t, true, off["unavailable"])
	assert.Equal(t, []any{}, off["items"])
	assert.Nil(t, h.server.Concerts.Concert(context.Background(), "Z1"))
}

func TestConcertsNearUseTheSavedCityOrAOneOffPoint(t *testing.T) {
	fake := newFakeConcerts()
	at := "21:00"
	fake.nearConcerts = []concerts.Concert{sampleConcert("E1", "2026-11-02", &at)}
	h := newHarness(t, withConcerts(fake))
	_, bearer := h.signIn()

	missing := h.do(http.MethodPost, "/v1/concerts/near", bearer, map[string]any{"radiusKm": 50})
	assert.Equal(t, http.StatusConflict, missing.Code)
	assert.Equal(t, "no_place", decode[map[string]any](t, missing)["code"])

	saved := decode[map[string]any](t, h.do(http.MethodPut, "/v1/me/concert-place", bearer, map[string]any{
		"name": " Lisbon ", "country": "Portugal", "countryCode": "pt", "latitude": 38.71667, "longitude": -9.13333,
	}))
	assert.Equal(t, true, saved["available"])
	place := saved["place"].(map[string]any)
	assert.Equal(t, "Lisbon", place["name"])
	assert.Equal(t, "PT", place["countryCode"])
	assert.InDelta(t, 38.72, place["latitude"], 0)
	assert.InDelta(t, -9.13, place["longitude"], 0)

	fromCity := decode[map[string]any](t, h.do(http.MethodPost, "/v1/concerts/near", bearer, map[string]any{"radiusKm": 25}))
	assert.Equal(t, "Lisbon", fromCity["place"].(map[string]any)["name"])
	items := fromCity["items"].([]any)
	first := items[0].(map[string]any)
	assert.Equal(t, "E1", first["id"])
	assert.InDelta(t, 1.2, first["distanceKm"], 0)
	assert.Equal(t, concerts.GeoPoint{Latitude: 38.72, Longitude: -9.13}, fake.lastNear())
	assert.Equal(t, 25, fake.nearRadii[len(fake.nearRadii)-1])

	oneOff := decode[map[string]any](t, h.do(http.MethodPost, "/v1/concerts/near", bearer, map[string]any{
		"latitude": 41.14961, "longitude": -8.61099, "radiusKm": 100,
	}))
	assert.NotContains(t, oneOff, "place", "a one-off position is not the saved city")
	assert.Equal(t, concerts.GeoPoint{Latitude: 41.15, Longitude: -8.61}, fake.lastNear())

	half := h.do(http.MethodPost, "/v1/concerts/near", bearer, map[string]any{"latitude": 41.1, "radiusKm": 50})
	assert.Equal(t, http.StatusUnprocessableEntity, half.Code)
	farPage := h.do(http.MethodPost, "/v1/concerts/near", bearer, map[string]any{"radiusKm": 50, "page": 11})
	assert.Equal(t, http.StatusUnprocessableEntity, farPage.Code)
	assert.Equal(t, "Pages run from 1 to 10.", decode[map[string]any](t, farPage)["message"])

	assert.Equal(t, http.StatusNoContent, h.do(http.MethodDelete, "/v1/me/concert-place", bearer, nil).Code)
	assert.NotContains(t, decode[map[string]any](t, h.do(http.MethodGet, "/v1/me/concert-place", bearer, nil)), "place")
}

func TestConcertsAreCachedPerAreaAndServedStaleOnFailure(t *testing.T) {
	fake := newFakeConcerts()
	fake.nearConcerts = []concerts.Concert{sampleConcert("E1", "2026-11-02", nil)}
	h := newHarness(t, withConcerts(fake))
	userID, _ := h.signIn()
	service := h.server.Concerts
	start := time.Now()
	service.Now = func() time.Time { return start }
	ctx := context.Background()
	lisbon := concerts.GeoPoint{Latitude: 38.72, Longitude: -9.14}
	// A point in the same ~5 km cell shares the answer.
	nearby := concerts.GeoPoint{Latitude: 38.73, Longitude: -9.13}
	_, err := service.Near(ctx, userID, &lisbon, 50, 1)
	require.NoError(t, err)
	second, err := service.Near(ctx, userID, &nearby, 50, 1)
	require.NoError(t, err)
	assert.Len(t, fake.nearCalls, 1)
	assert.Equal(t, "E1", second.Results.Concerts[0].ID)

	fake.fail(true)
	service.Now = func() time.Time { return start.Add(7 * time.Hour) }
	stale, err := service.Near(ctx, userID, &lisbon, 50, 1)
	require.NoError(t, err)
	assert.Len(t, fake.nearCalls, 2)
	assert.Equal(t, "E1", stale.Results.Concerts[0].ID)
	assert.False(t, stale.Unavailable)

	porto := concerts.GeoPoint{Latitude: 41.15, Longitude: -8.61}
	elsewhere, err := service.Near(ctx, userID, &porto, 50, 1)
	require.NoError(t, err)
	assert.True(t, elsewhere.Unavailable, "nothing cached for that area")
}

func TestYourArtistsOnTourMatchByMusicBrainzIDOnly(t *testing.T) {
	fake := newFakeConcerts()
	h := newHarness(t, withConcerts(fake))
	userID, bearer := h.signIn()
	ctx := context.Background()
	album := uuid.NewString()
	titleID := uuid.New()
	_, err := h.pool.Exec(ctx, `INSERT INTO titles (id, type, title, musicbrainz) VALUES ($1, 'album', 'OK Computer', $2)`, titleID, album)
	require.NoError(t, err)
	_, err = h.pool.Exec(ctx, `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at)
		VALUES ($1, $2, $3, 'wishlist', now(), now())`, uuid.New(), userID, titleID)
	require.NoError(t, err)

	radiohead, namesake := uuid.NewString(), uuid.NewString()
	fake.artistsByAlbum[album] = []concerts.MusicArtist{
		{MusicBrainzID: radiohead, Name: "Radiohead " + radiohead},
		{MusicBrainzID: namesake, Name: "Namesake " + namesake},
		{MusicBrainzID: concerts.VariousArtists, Name: "Various Artists"},
	}
	fake.attractionsBy["Radiohead "+radiohead] = []concerts.Attraction{
		{ID: "K-tribute", Name: "Radiohead " + radiohead, MusicBrainzIDs: []string{"someone-else"}},
		{ID: "K-real", Name: "Radiohead", MusicBrainzIDs: []string{radiohead}},
	}
	// Same name, no MusicBrainz link: never a match.
	fake.attractionsBy["Namesake "+namesake] = []concerts.Attraction{{ID: "K-namesake", Name: "Namesake " + namesake}}
	fake.byAttraction["K-real"] = []concerts.Concert{sampleConcert("E9", "2026-12-01", nil), sampleConcert("E8", "2026-11-20", nil)}

	before := decode[map[string]any](t, h.do(http.MethodGet, "/v1/concerts/artists", bearer, nil))
	assert.InDelta(t, 0, before["matched"], 0)
	assert.Equal(t, []any{}, before["items"])

	refresher := concerts.NewRefresher(h.server.Concerts.Store, fake, fake)
	refresher.AlbumLimit, refresher.ArtistLimit = 10000, 10000
	albums, err := refresher.FillAlbumArtists(ctx)
	require.NoError(t, err)
	assert.Equal(t, 1, albums)
	pending := decode[map[string]any](t, h.do(http.MethodGet, "/v1/concerts/artists", bearer, nil))
	assert.InDelta(t, 3, pending["pending"], 0)

	_, err = refresher.MatchArtists(ctx)
	require.NoError(t, err)
	assert.NotContains(t, fake.attractionCalls, "Various Artists")
	after := decode[map[string]any](t, h.do(http.MethodGet, "/v1/concerts/artists", bearer, nil))
	assert.InDelta(t, 1, after["matched"], 0)
	assert.InDelta(t, 0, after["pending"], 0)
	var ids []string
	for _, item := range after["items"].([]any) {
		ids = append(ids, item.(map[string]any)["id"].(string))
	}
	assert.Equal(t, []string{"E8", "E9"}, ids, "soonest first")
	assert.NotContains(t, after["items"].([]any)[0].(map[string]any), "venuePoint")
	assert.Equal(t, []string{"K-real"}, fake.performingCalls[len(fake.performingCalls)-1])

	_, err = refresher.MatchArtists(ctx)
	require.NoError(t, err)
	count := 0
	for _, name := range fake.attractionCalls {
		if strings.Contains(name, radiohead) {
			count++
		}
	}
	assert.Equal(t, 1, count, "a matched artist waits a month")
}

func TestAConcertByIDIsCachedAndNeverAnError(t *testing.T) {
	fake := newFakeConcerts()
	fake.eventsByID["Z1"] = sampleConcert("Z1", "2026-11-02", nil)
	h := newHarness(t, withConcerts(fake))
	ctx := context.Background()
	assert.Equal(t, "Show Z1", h.server.Concerts.Concert(ctx, "Z1").Name)
	assert.Equal(t, "Show Z1", h.server.Concerts.Concert(ctx, "Z1").Name)
	assert.Equal(t, []string{"Z1"}, fake.eventCalls, "the second open is served from the cache")
	fake.fail(true)
	assert.Nil(t, h.server.Concerts.Concert(ctx, "Z2"))
}

func searchFake() *fakeConcerts {
	fake := newFakeConcerts()
	madrid := sampleConcert("E1", "2026-11-02", nil)
	madrid.DistanceKm = nil
	madrid.VenuePoint = &concerts.GeoPoint{Latitude: 40.42, Longitude: -3.70}
	unknown := sampleConcert("E2", "2026-11-03", nil)
	unknown.DistanceKm = nil
	fake.searchConcerts = []concerts.Concert{madrid, unknown}
	return fake
}

func TestConcertSearchNearNeedsAPlace(t *testing.T) {
	fake := searchFake()
	h := newHarness(t, withConcerts(fake))
	_, bearer := h.signIn()
	missing := h.do(http.MethodPost, "/v1/concerts/search", bearer, map[string]any{"q": "Radiohead", "scope": "near", "radiusKm": 50})
	assert.Equal(t, http.StatusConflict, missing.Code)
	assert.Equal(t, "no_place", decode[map[string]any](t, missing)["code"])
	assert.Empty(t, fake.searchCalls)

	h.do(http.MethodPut, "/v1/me/concert-place", bearer, map[string]any{"name": "Lisbon", "latitude": 38.72, "longitude": -9.14})
	fromCity := decode[map[string]any](t, h.do(http.MethodPost, "/v1/concerts/search", bearer, map[string]any{
		"q": "Radiohead", "scope": "near", "radiusKm": 25,
	}))
	assert.InDelta(t, 25, fromCity["radiusKm"], 0)
	assert.Equal(t, "near", fromCity["scope"])
	assert.Equal(t, "Lisbon", fromCity["place"].(map[string]any)["name"])
	area := fake.searchAreas[len(fake.searchAreas)-1]
	assert.Equal(t, concerts.Area{Point: concerts.GeoPoint{Latitude: 38.72, Longitude: -9.14}, RadiusKm: 25}, *area)

	oneOff := decode[map[string]any](t, h.do(http.MethodPost, "/v1/concerts/search", bearer, map[string]any{
		"q": "Radiohead", "scope": "near", "radiusKm": 50, "latitude": 41.14961, "longitude": -8.61099,
	}))
	assert.NotContains(t, oneOff, "place", "a one-off position is not the saved city")
	assert.Equal(t, concerts.GeoPoint{Latitude: 41.15, Longitude: -8.61}, fake.searchAreas[len(fake.searchAreas)-1].Point)
}

func TestConcertSearchAnywhereMeasuresOnTheServer(t *testing.T) {
	fake := searchFake()
	h := newHarness(t, withConcerts(fake))
	_, bearer := h.signIn()
	nowhere := decode[map[string]any](t, h.do(http.MethodPost, "/v1/concerts/search", bearer, map[string]any{
		"q": " Radiohead ", "scope": "anywhere", "radiusKm": 50,
	}))
	assert.Equal(t, "Radiohead", nowhere["query"])
	assert.Equal(t, "anywhere", nowhere["scope"])
	assert.NotContains(t, nowhere, "radiusKm")
	assert.NotContains(t, nowhere, "place")
	for _, item := range nowhere["items"].([]any) {
		assert.NotContains(t, item.(map[string]any), "distanceKm", "no centre, no distance")
	}
	assert.Equal(t, concerts.Match{Keyword: "Radiohead"}, fake.searchCalls[0])
	assert.Nil(t, fake.searchAreas[0])

	h.do(http.MethodPut, "/v1/me/concert-place", bearer, map[string]any{"name": "Lisbon", "latitude": 38.72, "longitude": -9.14})
	fromCity := decode[map[string]any](t, h.do(http.MethodPost, "/v1/concerts/search", bearer, map[string]any{
		"q": "RADIOHEAD", "scope": "anywhere", "radiusKm": 50,
	}))
	assert.Len(t, fake.searchCalls, 1, "the same name in any case is one cached search")
	assert.Equal(t, "Lisbon", fromCity["place"].(map[string]any)["name"])
	measured := fromCity["items"].([]any)
	assert.InDelta(t, 502, measured[0].(map[string]any)["distanceKm"], 3, "Lisbon to Madrid, worked out by the server")
	assert.NotContains(t, measured[1].(map[string]any), "distanceKm", "a venue without a position has no distance")
	assert.NotContains(t, measured[0].(map[string]any), "venuePoint", "the venue's position stays on the server")
}

func TestConcertPerformersForAName(t *testing.T) {
	fake := searchFake()
	for i := 1; i <= 10; i++ {
		fake.attractionsBy["Radiohead"] = append(fake.attractionsBy["Radiohead"], concerts.Attraction{ID: fmt.Sprintf("K%d", i), Name: fmt.Sprintf("Radiohead %d", i)})
	}
	fake.attractionsBy["Radiohead"] = append(fake.attractionsBy["Radiohead"], concerts.Attraction{ID: "K1", Name: "Radiohead"})
	h := newHarness(t, withConcerts(fake))
	_, bearer := h.signIn()
	list := decode[map[string]any](t, h.do(http.MethodPost, "/v1/concerts/performers", bearer, map[string]any{"q": " Radiohead "}))
	var ids []string
	for _, item := range list["items"].([]any) {
		ids = append(ids, item.(map[string]any)["id"].(string))
	}
	assert.Equal(t, []string{"K1", "K2", "K3", "K4", "K5", "K6", "K7", "K8"}, ids)
	assert.Equal(t, false, list["unavailable"])
	h.do(http.MethodPost, "/v1/concerts/performers", bearer, map[string]any{"q": "RADIOHEAD"})
	assert.Len(t, fake.attractionCalls, 1, "one call per name")
	assert.Equal(t, http.StatusUnprocessableEntity, h.do(http.MethodPost, "/v1/concerts/performers", bearer, map[string]any{"q": "R"}).Code)
}

func TestConcertSearchByAPickedPerformer(t *testing.T) {
	fake := searchFake()
	h := newHarness(t, withConcerts(fake))
	_, bearer := h.signIn()
	picked := decode[map[string]any](t, h.do(http.MethodPost, "/v1/concerts/search", bearer, map[string]any{
		"q": "Radiohead", "performerId": "K8vZ917G", "scope": "anywhere", "radiusKm": 50,
	}))
	assert.Equal(t, "K8vZ917G", picked["performerId"])
	assert.Equal(t, "Radiohead", picked["query"])
	assert.Equal(t, concerts.Match{PerformerID: "K8vZ917G"}, fake.searchCalls[0])

	h.do(http.MethodPost, "/v1/concerts/search", bearer, map[string]any{"q": "Radiohead", "scope": "anywhere", "radiusKm": 50})
	assert.Len(t, fake.searchCalls, 2, "free text is its own search, not the performer's cache")
	assert.Equal(t, concerts.Match{Keyword: "Radiohead"}, fake.searchCalls[1])

	for _, bad := range []string{"", "K8v Z9", "K8vZ917G?x=1", strings.Repeat("K", 65)} {
		response := h.do(http.MethodPost, "/v1/concerts/search", bearer, map[string]any{
			"q": "Radiohead", "performerId": bad, "scope": "anywhere", "radiusKm": 50,
		})
		assert.Equal(t, http.StatusUnprocessableEntity, response.Code, bad)
	}
}

func TestConcertSearchValidation(t *testing.T) {
	h := newHarness(t, withConcerts(searchFake()))
	_, bearer := h.signIn()
	for _, bad := range []string{"R", strings.Repeat("x", 101), "   "} {
		response := h.do(http.MethodPost, "/v1/concerts/search", bearer, map[string]any{"q": bad, "scope": "anywhere", "radiusKm": 50})
		assert.Equal(t, http.StatusUnprocessableEntity, response.Code)
	}
	half := h.do(http.MethodPost, "/v1/concerts/search", bearer, map[string]any{
		"q": "Radiohead", "scope": "anywhere", "radiusKm": 50, "latitude": 41.1,
	})
	assert.Equal(t, http.StatusUnprocessableEntity, half.Code)
	short := h.do(http.MethodGet, "/v1/concerts/places?q=L", bearer, nil)
	assert.Equal(t, http.StatusUnprocessableEntity, short.Code)
}
