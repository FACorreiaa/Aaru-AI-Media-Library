package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// CAT-011 against canned TVmaze JSON.

func tmdbEpisodes(dates ...string) Episodes {
	e := Episodes{Status: ptr(StatusReturning), Network: ptr("TMDB Network")}
	for i, d := range dates {
		e.Episodes = append(e.Episodes, Episode{Season: 1, Episode: i + 1, AirsAt: ParseDay(&d), RuntimeMinutes: ptr(50)})
	}
	return e
}

func TestTVmazeRefinesAirTimes(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		switch urlPath(req.URL) {
		case "/lookup/shows":
			assert.Equal(t, "thetvdb=81189", urlQuery(req.URL).Encode())
			return provider.Response{Status: 200, Body: []byte(`{"id":169,"network":{"name":"AMC"}}`)}
		case "/shows/169/episodes":
			return provider.Response{Status: 200, Body: []byte(`[{"season":1,"number":1,"airstamp":"2026-10-20T01:00:00+00:00"},
			 {"season":1,"number":2,"airstamp":"2026-10-27T01:00:00+00:00"},
			 {"season":0,"number":null,"airstamp":"2026-10-01T01:00:00+00:00"}]`)}
		}
		return provider.Response{Status: 404}
	})
	refined, err := (&TVmaze{Client: testClient(stub, "tvmaze")}).Refine(context.Background(),
		tmdbEpisodes("2026-10-20", "2026-10-27", "2026-11-03"), core.ExternalIDs{IMDB: "tt0903747", TVDB: "81189"})
	require.NoError(t, err)
	assert.Equal(t, time.Date(2026, 10, 20, 1, 0, 0, 0, time.UTC), *refined.Episodes[0].AirsAt)
	assert.Equal(t, []bool{true, true, false}, []bool{refined.Episodes[0].AirTimeKnown, refined.Episodes[1].AirTimeKnown, refined.Episodes[2].AirTimeKnown})
	assert.Equal(t, *ParseDay(ptr("2026-11-03")), *refined.Episodes[2].AirsAt, "no TVmaze row: TMDB date kept")
	assert.Equal(t, "AMC", *refined.Network)
}

func TestTVmazeIgnoresMismatchedNumbering(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		if urlPath(req.URL) == "/lookup/shows" {
			return provider.Response{Status: 200, Body: []byte(`{"id":7,"webChannel":{"name":"Netflix"}}`)}
		}
		return provider.Response{Status: 200, Body: []byte(`[{"season":1,"number":1,"airstamp":"2020-01-01T08:00:00+00:00"}]`)}
	})
	refined, err := (&TVmaze{Client: testClient(stub, "tvmaze")}).Refine(context.Background(), tmdbEpisodes("2026-10-20"), core.ExternalIDs{TVDB: "1"})
	require.NoError(t, err)
	assert.False(t, refined.Episodes[0].AirTimeKnown)
	assert.Equal(t, *ParseDay(ptr("2026-10-20")), *refined.Episodes[0].AirsAt)
	assert.Equal(t, "Netflix", *refined.Network, "a streaming-only show's web channel is its network")
}

func TestTVmazeUnknownShowIsUnchanged(t *testing.T) {
	stub := stubFunc(func(provider.Request) provider.Response { return provider.Response{Status: 404} })
	original := tmdbEpisodes("2026-10-20")
	refined, err := (&TVmaze{Client: testClient(stub, "tvmaze")}).Refine(context.Background(), original, core.ExternalIDs{IMDB: "tt1", TVDB: "2"})
	require.NoError(t, err)
	assert.Equal(t, original, refined)
	var queries []string
	for _, r := range stub.all() {
		queries = append(queries, urlQuery(r.URL).Encode())
	}
	assert.Equal(t, []string{"thetvdb=2", "imdb=tt1"}, queries)
}
