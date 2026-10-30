package catalog

import (
	"context"
	"encoding/json"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/testdb"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// The Seasons view (DISC-002): season keys, provider queries, the page cache.

func constant(body string) *stubTransport {
	return stubFunc(func(provider.Request) provider.Response { return provider.Response{Status: 200, Body: []byte(body)} })
}

func TestSeasonKeysCrossTheYearEnd(t *testing.T) {
	fall := SeasonKey{Season: Fall, Year: 2026}
	assert.Equal(t, SeasonKey{Season: Winter, Year: 2027}, fall.Next())
	assert.Equal(t, fall, fall.Next().Previous())
	assert.Equal(t, SeasonKey{Season: Winter, Year: 2026}, SeasonKey{Season: Spring, Year: 2026}.Previous())
	assert.Equal(t, "Fall 2026", fall.Title())
}

func TestSeasonDaysAreItsQuarter(t *testing.T) {
	for _, c := range []struct {
		season      SeasonOfYear
		first, last string
	}{{Winter, "2026-01-01", "2026-03-31"}, {Spring, "2026-04-01", "2026-06-30"}, {Summer, "2026-07-01", "2026-09-30"}, {Fall, "2026-10-01", "2026-12-31"}} {
		first, last := SeasonKey{Season: c.season, Year: 2026}.Days()
		assert.Equal(t, c.first, first)
		assert.Equal(t, c.last, last)
	}
}

func TestAniListSeasonPage(t *testing.T) {
	transport := constant(`{"data":{"Page":{"pageInfo":{"hasNextPage":true,"total":84},"media":[
	  {"id":195516,"idMal":1,"format":"TV","status":"RELEASING","title":{"english":"Apothecary Diaries"},
	   "startDate":{"year":2026},"coverImage":{"large":"https://img/a.jpg"}}]}}}`)
	page, err := (&AniList{Client: testClient(transport, "anilist")}).Season(context.Background(), SeasonKey{Season: Spring, Year: 2025}, SeasonAnime, 2, discoverNow)
	require.NoError(t, err)
	require.Len(t, page.Hits, 1)
	assert.Equal(t, "195516", page.Hits[0].IDs.AniList)
	assert.True(t, page.HasMore)
	assert.Equal(t, 84, *page.Total)
	var body struct {
		Query     string         `json:"query"`
		Variables map[string]any `json:"variables"`
	}
	require.NoError(t, json.Unmarshal(transport.first(t).Body, &body))
	assert.Equal(t, "SPRING", body.Variables["season"])
	assert.InDelta(t, 2025, body.Variables["year"], 0)
	assert.InDelta(t, 2, body.Variables["page"], 0)
	assert.Contains(t, body.Query, "sort: POPULARITY_DESC")
	assert.Contains(t, body.Query, "isAdult: false")
}

func TestTMDBSeasonFiltersByTheSeasonsDates(t *testing.T) {
	for _, c := range []struct {
		kind     SeasonKind
		path     string
		expected map[string]string
	}{
		{SeasonShowsNew, "/discover/tv", map[string]string{"first_air_date.gte": "2026-10-01", "first_air_date.lte": "2026-12-31"}},
		{SeasonShowsReturning, "/discover/tv", map[string]string{"air_date.gte": "2026-10-01", "air_date.lte": "2026-12-31", "first_air_date.lte": "2026-09-30"}},
		{SeasonMovies, "/discover/movie", map[string]string{"primary_release_date.gte": "2026-10-01", "primary_release_date.lte": "2026-12-31"}},
	} {
		transport := constant(`{"results":[],"total_pages":3,"total_results":55}`)
		page, err := (&TMDB{Client: testClient(transport, "tmdb"), APIKey: "k"}).Season(context.Background(), SeasonKey{Season: Fall, Year: 2026}, c.kind, 1, discoverNow)
		require.NoError(t, err)
		req := transport.first(t)
		assert.Equal(t, c.path, urlPath(req.URL)[len(urlPath(req.URL))-len(c.path):])
		q := urlQuery(req.URL)
		for k, v := range c.expected {
			assert.Equal(t, v, q.Get(k), k)
		}
		assert.Equal(t, "popularity.desc", q.Get("sort_by"))
		// The current season has no votes yet: no floor.
		assert.Empty(t, q.Get("vote_count.gte"))
		assert.True(t, page.HasMore)
		assert.Equal(t, 55, *page.Total)
	}
}

func TestTMDBEndedSeasonKeepsAVoteFloor(t *testing.T) {
	transport := constant(`{"results":[
	  {"id":1,"name":"Drama","poster_path":"/d.jpg","genre_ids":[18],"original_language":"en"},
	  {"id":2,"name":"Anime","poster_path":"/a.jpg","genre_ids":[16],"original_language":"ja"}],
	 "total_pages":2,"total_results":30}`)
	page, err := (&TMDB{Client: testClient(transport, "tmdb"), APIKey: "k"}).Season(context.Background(), SeasonKey{Season: Summer, Year: 2025}, SeasonShowsNew, 2, discoverNow)
	require.NoError(t, err)
	assert.Equal(t, "10", urlQuery(transport.first(t).URL).Get("vote_count.gte"))
	// Anime shows come from AniList's tab.
	assert.Equal(t, []string{"Drama"}, titlesOf(page.Hits))
	assert.False(t, page.HasMore)
}

func TestSeasonCacheIsKeyedAndBounded(t *testing.T) {
	cache := newSharedCache[string, SeasonPage](SeasonCacheCapacity, "test")
	var calls atomic.Int32
	fetch := func(context.Context) (SeasonPage, error) { calls.Add(1); return SeasonPage{}, nil }
	ttl := func(SeasonPage) time.Duration { return time.Minute }
	get := func(key string, at time.Time) { cache.get(context.Background(), key, at, ttl, fetch) }
	get("a", discoverNow)
	get("a", discoverNow.Add(30*time.Second))
	assert.Equal(t, int32(1), calls.Load())
	get("a", discoverNow.Add(61*time.Second))
	assert.Equal(t, int32(2), calls.Load())
	for i := 0; i <= SeasonCacheCapacity; i++ {
		get("k"+strconv.Itoa(i), discoverNow.Add(time.Duration(i)*time.Second))
	}
	cache.mu.Lock()
	defer cache.mu.Unlock()
	assert.Len(t, cache.entries, SeasonCacheCapacity)
}

type brokenSeasons struct{}

func (brokenSeasons) SeasonKinds() []SeasonKind { return []SeasonKind{SeasonAnime} }

func (brokenSeasons) Season(context.Context, SeasonKey, SeasonKind, int, time.Time) (SeasonPage, error) {
	return SeasonPage{}, provider.NewError("anilist", provider.KindUnauthorized)
}

func TestFailingSeasonReadsAsUnavailable(t *testing.T) {
	service := NewDiscoverService(NewStore(testdb.New(t)), []any{brokenSeasons{}}, nil, nil, nil)
	service.Now = func() time.Time { return discoverNow }
	result, err := service.Season(context.Background(), SeasonKey{Season: Fall, Year: 2026}, SeasonAnime, 1, uuid.New())
	require.NoError(t, err)
	assert.True(t, result.Unavailable)
	assert.Empty(t, result.Items)
}

func TestSeasonMarksOwnedAndDropsPosterless(t *testing.T) {
	env := newRefreshEnv(t)
	owned := env.title(core.MediaMovie, "Owned", core.ExternalIDs{TMDB: "4242"})
	env.track(owned.ID, "wishlist")
	var itemID uuid.UUID
	require.NoError(t, env.pool.QueryRow(env.ctx, `SELECT id FROM library_items WHERE title_id = $1`, owned.ID).Scan(&itemID))
	fake := newFake()
	fake.stubSeason(SeasonMovies, []Hit{
		discoverHit("Owned", core.MediaMovie, "4242", true), discoverHit("New", core.MediaMovie, "x-1", true),
		discoverHit("No poster", core.MediaMovie, "x-2", false),
	})
	service := NewDiscoverService(env.store, []any{fake}, nil, nil, nil)
	service.Now = func() time.Time { return discoverNow }
	result, err := service.Season(env.ctx, SeasonKey{Season: Fall, Year: 2026}, SeasonMovies, 1, env.user)
	require.NoError(t, err)
	assert.False(t, result.Unavailable)
	require.Len(t, result.Items, 2)
	assert.Equal(t, []string{"Owned", "New"}, []string{result.Items[0].Hit.Title, result.Items[1].Hit.Title})
	assert.Equal(t, itemID, *result.Items[0].LibraryItemID)
	assert.Nil(t, result.Items[1].LibraryItemID)

	for _, c := range []struct{ year, page int }{{1969, 1}, {2028, 1}, {2026, 0}, {2026, 21}} {
		_, err := service.Season(env.ctx, SeasonKey{Season: Fall, Year: c.year}, SeasonAnime, c.page, env.user)
		require.Error(t, err)
		assert.Contains(t, err.Error(), "must be between")
	}
	_, err = service.Season(env.ctx, SeasonKey{Season: Winter, Year: 2027}, SeasonAnime, 1, env.user)
	assert.NoError(t, err, "next year's seasons are open")
}
