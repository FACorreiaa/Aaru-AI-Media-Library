package concerts

import (
	"aaru-go-api/internal/provider"
	"context"
	"math"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// stub is a provider answering every request with respond, recording what it was asked.
type stub struct {
	mu       sync.Mutex
	requests []*url.URL
	server   *httptest.Server
}

func newStub(t *testing.T, respond func(r *http.Request) (int, string)) *stub {
	t.Helper()
	s := &stub{}
	s.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		s.requests = append(s.requests, r.URL)
		s.mu.Unlock()
		status, body := respond(r)
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(s.server.Close)
	return s
}

func (s *stub) asked() []*url.URL {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]*url.URL(nil), s.requests...)
}

func testClient(name string) *provider.Client {
	return provider.NewClient(name, provider.NewHTTPTransport(), provider.NewPacer(1000, 100))
}

func adapter(s *stub, budget int) *Ticketmaster {
	return &Ticketmaster{Client: testClient("ticketmaster"), APIKey: "test-key", Budget: NewCallBudget(budget), BaseURL: s.server.URL}
}

func query(u *url.URL) map[string]string {
	out := map[string]string{}
	for k, v := range u.Query() {
		out[k] = v[0]
	}
	return out
}

func TestPointsAreRoundedAndHashed(t *testing.T) {
	point, ok := NewGeoPoint(38.72345, -9.13987)
	require.True(t, ok)
	assert.Equal(t, GeoPoint{Latitude: 38.72, Longitude: -9.14}, point)
	_, ok = NewGeoPoint(91, 0)
	assert.False(t, ok)
	_, ok = NewGeoPoint(nan(), 0)
	assert.False(t, ok)
	// Wikipedia's worked example.
	p, _ := NewGeoPoint(42.6, -5.6)
	assert.Equal(t, "ezs42", p.Geohash())
}

func TestDistancesAreGreatCircleKilometres(t *testing.T) {
	lisbon, _ := NewGeoPoint(38.72, -9.14)
	madrid, _ := NewGeoPoint(40.42, -3.70)
	assert.InDelta(t, 502, lisbon.DistanceKm(madrid), 3)
	assert.InDelta(t, 0, lisbon.DistanceKm(lisbon), 0)
}

const tmEvents = `{"_embedded":{"events":[
  {"id":"E1","name":"Radiohead","url":"https://www.ticketmaster.pt/event/E1",
   "dates":{"start":{"localDate":"2026-11-02","localTime":"21:00:00","dateTime":"2026-11-02T21:00:00Z"},
            "status":{"code":"onsale"}},
   "distance":3.4,"units":"KILOMETERS",
   "images":[{"url":"https://s1.ticketm.net/fallback.jpg","ratio":"16_9","width":640,"fallback":true},
             {"url":"https://s1.ticketm.net/small.jpg","ratio":"16_9","width":205,"fallback":false},
             {"url":"https://s1.ticketm.net/wide.jpg","ratio":"16_9","width":640,"fallback":false}],
   "_embedded":{"venues":[{"name":"MEO Arena","city":{"name":"Lisboa"},"country":{"name":"Portugal"}}],
                "attractions":[{"name":"Radiohead"},{"name":"Support"}]}},
  {"id":"E2","name":"Cancelled","url":"https://www.ticketmaster.pt/event/E2",
   "dates":{"start":{"localDate":"2026-11-03"},"status":{"code":"cancelled"}}},
  {"id":"E3","name":"Time to be announced","url":"https://www.ticketmaster.pt/event/E3","distance":10,
   "units":"MILES","dates":{"start":{"localDate":"2026-11-04","localTime":"20:00:00","timeTBA":true}}},
  {"id":"E4","name":"No date","url":"https://www.ticketmaster.pt/event/E4","dates":{"start":{}}}
]},"page":{"size":50,"totalElements":120,"totalPages":3,"number":0}}`

func TestNearSendsTheCellRadiusAndPaging(t *testing.T) {
	s := newStub(t, func(*http.Request) (int, string) { return 200, tmEvents })
	point, _ := NewGeoPoint(42.6, -5.6)
	results, err := adapter(s, 100).Near(context.Background(), point, 50, 1, time.Unix(1_792_000_000, 0))
	require.NoError(t, err)

	asked := s.asked()
	require.Len(t, asked, 1)
	assert.Equal(t, "/events.json", asked[0].Path)
	q := query(asked[0])
	assert.Equal(t, "ezs42", q["geoPoint"])
	assert.Equal(t, "50", q["radius"])
	assert.Equal(t, "km", q["unit"])
	assert.Equal(t, "music", q["classificationName"])
	assert.Equal(t, "date,asc", q["sort"])
	assert.Equal(t, "0", q["page"])
	assert.Equal(t, "50", q["size"])
	assert.Equal(t, "2026-10-14T17:46:40Z", q["startDateTime"])
	assert.Equal(t, "test-key", q["apikey"])
	assert.NotContains(t, q, "latlong", "the exact point is never sent, only its cell")
	assert.True(t, strings.HasSuffix(asked[0].RawQuery, "&apikey=test-key"))

	ids := []string{}
	for _, c := range results.Concerts {
		ids = append(ids, c.ID)
	}
	assert.Equal(t, []string{"E1", "E3"}, ids, "cancelled and undated events are left out")
	assert.True(t, results.HasMore)
	first := results.Concerts[0]
	assert.Equal(t, "2026-11-02", first.LocalDate)
	assert.Equal(t, "21:00", *first.LocalTime)
	assert.Equal(t, time.Unix(1_793_653_200, 0).UTC(), *first.StartsAt)
	assert.Equal(t, "MEO Arena", *first.Venue)
	assert.Equal(t, "Lisboa", *first.City)
	assert.Equal(t, "Portugal", *first.Country)
	assert.Equal(t, []string{"Radiohead", "Support"}, first.Artists)
	assert.InDelta(t, 3.4, *first.DistanceKm, 0)
	assert.Equal(t, "https://s1.ticketm.net/wide.jpg", *first.ImageURL)
	tba := results.Concerts[1]
	assert.Nil(t, tba.LocalTime, "a time to be announced is not shown")
	assert.Nil(t, tba.StartsAt)
	assert.InDelta(t, 16.09, *tba.DistanceKm, 0.01, "miles become kilometres")
}

func TestPerformersKeepTheirMusicBrainzIDsLowercased(t *testing.T) {
	s := newStub(t, func(*http.Request) (int, string) {
		return 200, `{"_embedded":{"attractions":[
		  {"id":"K8vZ917G","name":"Radiohead",
		   "externalLinks":{"musicbrainz":[{"id":"A74B1B7F-71A5-4011-9441-D0B5E4122711"}]}},
		  {"id":"K8vZ999","name":"Radiohead Tribute"}
		]}}`
	})
	found, err := adapter(s, 100).Attractions(context.Background(), "Radiohead")
	require.NoError(t, err)
	assert.Equal(t, []Attraction{
		{ID: "K8vZ917G", Name: "Radiohead", MusicBrainzIDs: []string{"a74b1b7f-71a5-4011-9441-d0b5e4122711"}},
		{ID: "K8vZ999", Name: "Radiohead Tribute", MusicBrainzIDs: []string{}},
	}, found)
	assert.Equal(t, "Radiohead", query(s.asked()[0])["keyword"])
	assert.Equal(t, "/attractions.json", s.asked()[0].Path)
}

func TestASpentBudgetFailsFastAndResetsTheNextUTCDay(t *testing.T) {
	budget := NewCallBudget(1)
	day := time.Unix(1_792_000_000, 0)
	assert.True(t, budget.Take(day))
	assert.False(t, budget.Take(day))
	assert.True(t, budget.Take(day.Add(24*time.Hour)))

	s := newStub(t, func(*http.Request) (int, string) { return 200, "{}" })
	_, err := adapter(s, 0).Attractions(context.Background(), "Radiohead")
	assert.ErrorIs(t, err, provider.NewError("ticketmaster", provider.KindUnavailable))
	assert.Empty(t, s.asked())
}

const tmSearchEvents = `{"_embedded":{"events":[
  {"id":"E1","name":"Radiohead","url":"https://www.ticketmaster.es/event/E1",
   "dates":{"start":{"localDate":"2026-11-02"}},
   "_embedded":{"venues":[{"name":"WiZink Center","city":{"name":"Madrid"},
                           "location":{"longitude":"-3.67200","latitude":"40.42400"}}]}},
  {"id":"E2","name":"Radiohead","url":"https://www.ticketmaster.es/event/E2",
   "dates":{"start":{"localDate":"2026-11-03"}},
   "_embedded":{"venues":[{"name":"Somewhere","location":{"longitude":"","latitude":"x"}}]}}
]},"page":{"totalPages":1,"number":0}}`

func TestSearchSendsTheAreaOnlyWhenNear(t *testing.T) {
	s := newStub(t, func(*http.Request) (int, string) { return 200, tmSearchEvents })
	tm := adapter(s, 100)
	point, _ := NewGeoPoint(42.6, -5.6)
	from := time.Unix(1_792_000_000, 0)
	ctx := context.Background()

	near, err := tm.Search(ctx, Match{Keyword: "Radiohead"}, &Area{Point: point, RadiusKm: 100}, 2, from)
	require.NoError(t, err)
	anywhere, err := tm.Search(ctx, Match{Keyword: "Radiohead"}, nil, 1, from)
	require.NoError(t, err)
	_, err = tm.Search(ctx, Match{PerformerID: "K8vZ917G"}, nil, 1, from)
	require.NoError(t, err)

	asked := s.asked()
	q0, q1, q2 := query(asked[0]), query(asked[1]), query(asked[2])
	assert.Equal(t, "Radiohead", q0["keyword"])
	assert.Equal(t, "music", q0["classificationName"])
	assert.Equal(t, "ezs42", q0["geoPoint"])
	assert.Equal(t, "100", q0["radius"])
	assert.Equal(t, "km", q0["unit"])
	assert.Equal(t, "1", q0["page"])
	assert.Equal(t, "date,asc", q0["sort"])
	assert.Equal(t, "Radiohead", q1["keyword"])
	assert.NotContains(t, q1, "geoPoint", "anywhere sends no area")
	assert.NotContains(t, q1, "radius")
	assert.Equal(t, "K8vZ917G", q2["attractionId"], "a picked performer, by id")
	assert.NotContains(t, q2, "keyword")
	assert.False(t, near.HasMore)
	madrid, _ := NewGeoPoint(40.424, -3.672)
	require.Len(t, anywhere.Concerts, 2)
	assert.Equal(t, &madrid, anywhere.Concerts[0].VenuePoint)
	assert.Nil(t, anywhere.Concerts[1].VenuePoint)
}

func TestPerformersCarryARealPicture(t *testing.T) {
	s := newStub(t, func(*http.Request) (int, string) {
		return 200, `{"_embedded":{"attractions":[
		  {"id":"K1","name":"Radiohead","images":[
		    {"url":"https://s1.ticketm.net/fallback.jpg","ratio":"16_9","width":205,"fallback":true},
		    {"url":"https://s1.ticketm.net/big.jpg","ratio":"16_9","width":1024,"fallback":false},
		    {"url":"https://s1.ticketm.net/small.jpg","ratio":"16_9","width":205,"fallback":false}]},
		  {"id":"K2","name":"Radiohead Tribute"}
		]}}`
	})
	found, err := adapter(s, 100).Attractions(context.Background(), "Radiohead")
	require.NoError(t, err)
	require.Len(t, found, 2)
	assert.Equal(t, "https://s1.ticketm.net/small.jpg", *found[0].ImageURL)
	assert.Nil(t, found[1].ImageURL)
}

const tmOneEvent = `{"id":"E1","name":"Radiohead","url":"https://www.ticketmaster.pt/event/E1",
 "dates":{"start":{"localDate":"2026-11-02","localTime":"21:00:00","dateTime":"2026-11-02T21:00:00Z"},
          "status":{"code":"onsale"}},
 "_embedded":{"venues":[{"name":"MEO Arena","city":{"name":"Lisboa"},"country":{"name":"Portugal"}}],
              "attractions":[{"name":"Radiohead"}]}}`

func TestAnEventByIDReadsOneEventAndA404IsNil(t *testing.T) {
	s := newStub(t, func(r *http.Request) (int, string) {
		if strings.HasSuffix(r.URL.Path, "/events/E1.json") {
			return 200, tmOneEvent
		}
		return 404, ""
	})
	concert, err := adapter(s, 100).Event(context.Background(), "E1")
	require.NoError(t, err)
	require.NotNil(t, concert)
	assert.Equal(t, "E1", concert.ID)
	assert.Equal(t, "Radiohead", concert.Name)
	assert.Equal(t, "MEO Arena", *concert.Venue)
	assert.Equal(t, "https://www.ticketmaster.pt/event/E1", concert.URL)
	missing, err := adapter(s, 100).Event(context.Background(), "E9")
	require.NoError(t, err)
	assert.Nil(t, missing)
}

func TestARowMissingARequiredFieldIsMalformed(t *testing.T) {
	s := newStub(t, func(*http.Request) (int, string) {
		return 200, `{"_embedded":{"events":[{"name":"no id","url":"https://x.test/e"}]}}`
	})
	_, err := adapter(s, 100).Near(context.Background(), GeoPoint{}, 25, 1, time.Now())
	assert.ErrorIs(t, err, provider.NewError("ticketmaster", provider.KindMalformed))
}

func TestOpenMeteoPlaces(t *testing.T) {
	s := newStub(t, func(*http.Request) (int, string) {
		return 200, `{"results":[{"name":"Lisbon","latitude":38.71667,"longitude":-9.13333,"country":"Portugal",
		  "country_code":"pt","admin1":"Lisbon"}]}`
	})
	places, err := (&OpenMeteo{Client: testClient("open-meteo"), BaseURL: s.server.URL}).Places(context.Background(), "Lisbon")
	require.NoError(t, err)
	require.Len(t, places, 1)
	assert.Equal(t, "PT", *places[0].CountryCode)
	assert.Equal(t, GeoPoint{Latitude: 38.72, Longitude: -9.13}, places[0].Point)
	q := query(s.asked()[0])
	assert.Equal(t, map[string]string{"name": "Lisbon", "count": "8", "language": "en", "format": "json"}, q)

	empty := newStub(t, func(*http.Request) (int, string) { return 200, `{"generationtime_ms":0.1}` })
	none, err := (&OpenMeteo{Client: testClient("open-meteo"), BaseURL: empty.server.URL}).Places(context.Background(), "Nowhere")
	require.NoError(t, err)
	assert.Empty(t, none, "absent results are no places")
}

func nan() float64 { return math.NaN() }
