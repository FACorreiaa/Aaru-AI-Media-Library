package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/provider"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// OnAirGuideTests.route over HTTP: channels by name with Other last, a region's services as
// streamsOn (the channel itself left out) with the watch link, the next episode's day without an
// exact time, no streamsOn at all for a show with no data in the region, and a bad region is 422.
// The library marking is covered by catalog.TestOnAirMarksOwnedAndListsTheRegionsServices.
func TestOnAirRouteGroupsByChannelAndListsServices(t *testing.T) {
	day := func(offset int) string { return time.Now().UTC().AddDate(0, 0, offset).Format(time.DateOnly) }
	tmdb := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/tv/on_the_air":
			_, _ = w.Write([]byte(`{"total_pages":1,"results":[
			 {"id":101,"name":"Owned","poster_path":"/o.jpg","genre_ids":[18],"original_language":"en"},
			 {"id":102,"name":"New","poster_path":"/n.jpg","genre_ids":[18],"original_language":"en"}]}`))
		case "/tv/101":
			_, _ = w.Write([]byte(`{"networks":[{"name":"Netflix"}],
			 "next_episode_to_air":{"air_date":"` + day(1) + `","season_number":1,"episode_number":2},
			 "watch/providers":{"results":{"US":{"link":"https://www.themoviedb.org/tv/101/watch?locale=US",
			   "flatrate":[{"provider_name":"Netflix","display_priority":1},{"provider_name":"Hulu","display_priority":2}]}}}}`))
		case "/tv/102":
			_, _ = w.Write([]byte(`{"next_episode_to_air":{"air_date":"` + day(0) + `","season_number":1,"episode_number":1}}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(tmdb.Close)
	client := provider.NewClient("tmdb", provider.NewHTTPTransport(), provider.NewPacer(1000, 100))
	client.MaxAttempts = 1
	providers := catalog.Providers{TMDB: &catalog.TMDB{Client: client, APIKey: "test", BaseURL: tmdb.URL}}
	h := newHarness(t, func(d *Deps) { d.Catalog = catalog.NewKit(d.Pool, providers, d.Log) })
	_, bearer := h.signIn()

	rec := h.do(http.MethodGet, "/v1/discover/on-air?region=us", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	channels := decode[map[string]any](t, rec)["channels"].([]any)
	var names []string
	for _, c := range channels {
		names = append(names, c.(map[string]any)["name"].(string))
	}
	require.Equal(t, []string{"Netflix", "Other"}, names)

	show := channels[0].(map[string]any)["shows"].([]any)[0].(map[string]any)
	assert.Equal(t, "Owned", show["item"].(map[string]any)["title"])
	streams := show["streamsOn"].([]any)
	require.Len(t, streams, 1)
	assert.Equal(t, "Hulu", streams[0].(map[string]any)["name"])
	assert.IsType(t, "", show["watchLink"])
	next := show["nextEpisode"].(map[string]any)
	assert.Equal(t, false, next["airTimeKnown"])
	assert.InDelta(t, 1, next["season"], 0)

	other := channels[1].(map[string]any)["shows"].([]any)[0].(map[string]any)
	_, has := other["streamsOn"]
	assert.False(t, has, "no data for the region: nothing rather than an empty list")
	_, has = other["watchLink"]
	assert.False(t, has)

	assert.Equal(t, http.StatusUnprocessableEntity, h.do(http.MethodGet, "/v1/discover/on-air?region=usa", bearer, nil).Code)
}
