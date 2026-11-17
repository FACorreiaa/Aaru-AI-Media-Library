package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTMDBWatchRegionsGroupServicesByRegion(t *testing.T) {
	stub := routes(map[string]string{
		"/movie/693134/watch/providers": `{"results":{
		  "pt":{"link":"https://www.themoviedb.org/movie/693134/watch?locale=PT",
		    "flatrate":[
		      {"provider_name":"Max","logo_path":"/max.jpg","display_priority":9},
		      {"provider_name":"Netflix","logo_path":"/nf.jpg","display_priority":1},
		      {"provider_name":"Max Amazon Channel","display_priority":2},
		      {"provider_name":"netflix","display_priority":3},
		      {"provider_name":"  ","display_priority":0}],
		    "rent":[{"provider_name":"Apple TV","logo_path":null,"display_priority":4}]},
		  "US":{"link":" ","buy":[{"provider_name":"Fandango At Home"}]},
		  "BR":{"link":"https://example.test","flatrate":[{"provider_name":"Paramount+ with Ads"}]}}}`,
	})
	regions, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}).
		WatchRegions(context.Background(), core.ExternalIDs{TMDB: "693134"}, core.MediaMovie)
	require.NoError(t, err)

	pt := regions["PT"]
	require.NotNil(t, pt.Link, "the region code is upper case whatever TMDB sends")
	assert.Equal(t, []WatchProvider{
		{Name: "Netflix", LogoURL: ptr(tmdbLogoBase + "/nf.jpg")},
		{Name: "Max", LogoURL: ptr(tmdbLogoBase + "/max.jpg")},
	}, pt.Streaming, "TMDB's order, without a reseller, a blank name or a name twice")
	assert.Equal(t, []WatchProvider{{Name: "Apple TV"}}, pt.Rent)
	assert.Empty(t, pt.Buy)

	us := regions["US"]
	assert.Nil(t, us.Link, "a blank link is no link")
	assert.Equal(t, []WatchProvider{{Name: "Fandango At Home"}}, us.Buy)

	_, listed := regions["BR"]
	assert.False(t, listed, "a region left with only resellers has nothing to show")
}

func TestTMDBWatchRegionsCapEachGroup(t *testing.T) {
	entries := ""
	for i := range WatchLimit + 3 {
		if i > 0 {
			entries += ","
		}
		entries += `{"provider_name":"Service ` + string(rune('A'+i)) + `"}`
	}
	stub := routes(map[string]string{"/tv/1/watch/providers": `{"results":{"GB":{"flatrate":[` + entries + `]}}}`})
	regions, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}).
		WatchRegions(context.Background(), core.ExternalIDs{TMDB: "1"}, core.MediaShow)
	require.NoError(t, err)
	assert.Len(t, regions["GB"].Streaming, WatchLimit)
}

func TestTMDBWatchRegionsKnowNothingOfOtherKindsOrMissingTitles(t *testing.T) {
	tmdb := &TMDB{Client: testClient(routes(map[string]string{}), "tmdb"), APIKey: "k"}
	regions, err := tmdb.WatchRegions(context.Background(), core.ExternalIDs{TMDB: "1"}, core.MediaBook)
	require.NoError(t, err)
	assert.Nil(t, regions, "not a kind TMDB has")
	regions, err = tmdb.WatchRegions(context.Background(), core.ExternalIDs{}, core.MediaMovie)
	require.NoError(t, err)
	assert.Nil(t, regions, "no id TMDB knows")
	regions, err = tmdb.WatchRegions(context.Background(), core.ExternalIDs{TMDB: "404"}, core.MediaMovie)
	require.NoError(t, err)
	assert.Nil(t, regions, "an id TMDB dropped is nothing to show, not a failure")
}

// countingWatch is a WatchSource that counts its calls.
type countingWatch struct {
	regions map[string]TitleWatch
	err     error
	calls   int
}

func (c *countingWatch) WatchRegions(context.Context, core.ExternalIDs, core.MediaType) (map[string]TitleWatch, error) {
	c.calls++
	return c.regions, c.err
}

func TestWatchServiceServesEveryRegionFromOneRead(t *testing.T) {
	source := &countingWatch{regions: map[string]TitleWatch{
		"PT": {Streaming: []WatchProvider{{Name: "Netflix"}}},
		"US": {Rent: []WatchProvider{{Name: "Apple TV"}}},
	}}
	now := time.Date(2026, 11, 17, 12, 0, 0, 0, time.UTC)
	service := NewWatchService(source, nil)
	service.Now = func() time.Time { return now }
	film := core.Title{ID: uuid.New(), Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: "1"}}

	pt := service.For(context.Background(), film, "PT")
	require.NotNil(t, pt)
	assert.Equal(t, "Netflix", pt.Streaming[0].Name)
	us := service.For(context.Background(), film, "US")
	require.NotNil(t, us)
	assert.Nil(t, service.For(context.Background(), film, "JP"), "a region with no data shows nothing")
	assert.Equal(t, 1, source.calls, "one provider read serves every region")

	now = now.Add(WatchTTL + time.Minute)
	require.NotNil(t, service.For(context.Background(), film, "PT"))
	assert.Equal(t, 2, source.calls, "read again once stale")
}

func TestWatchServiceShowsNothingForOtherKindsNoRegionOrAFailure(t *testing.T) {
	source := &countingWatch{regions: map[string]TitleWatch{"PT": {Streaming: []WatchProvider{{Name: "Netflix"}}}}}
	service := NewWatchService(source, nil)
	book := core.Title{ID: uuid.New(), Type: core.MediaBook}
	assert.Nil(t, service.For(context.Background(), book, "PT"))
	film := core.Title{ID: uuid.New(), Type: core.MediaMovie}
	assert.Nil(t, service.For(context.Background(), film, ""))
	assert.Zero(t, source.calls, "neither asks the provider")

	failing := NewWatchService(&countingWatch{err: errors.New("tmdb is down")}, nil)
	assert.Nil(t, failing.For(context.Background(), film, "PT"), "a provider that failed is nothing to show")

	var none *WatchService
	assert.Nil(t, none.For(context.Background(), film, "PT"))
	assert.Nil(t, NewWatchService(provider.Client{}, nil).For(context.Background(), film, "PT"), "no source configured")
}
