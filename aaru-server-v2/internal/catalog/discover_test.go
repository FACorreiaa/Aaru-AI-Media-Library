package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/testdb"
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Discover rows (DISC-001): provider lists, the shared cache, and the library mark.

// discoverNow is 2026-10-20T12:00:00Z.
var discoverNow = time.Unix(1_792_497_600, 0).UTC()

func discoverHit(title string, mediaType core.MediaType, tmdb string, poster bool) Hit {
	h := Hit{Type: mediaType, Title: title, Year: ptr(2026), IDs: core.ExternalIDs{TMDB: tmdb}}
	if poster {
		h.PosterURL = ptr("https://img/" + tmdb + ".jpg")
	}
	return h
}

func TestTMDBTVRowsLeaveOutAnimeAndTalkShows(t *testing.T) {
	stub := routes(map[string]string{"/trending/tv/week": `{"results":[
	  {"id":1,"name":"Drama","poster_path":"/d.jpg","genre_ids":[18],"original_language":"en"},
	  {"id":2,"name":"Anime","poster_path":"/a.jpg","genre_ids":[16],"original_language":"ja"},
	  {"id":3,"name":"Talk","poster_path":"/t.jpg","genre_ids":[10767],"original_language":"en"}]}`})
	hits, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}).List(context.Background(), ListTVTrending, discoverNow)
	require.NoError(t, err)
	assert.Equal(t, []string{"Drama"}, titlesOf(hits))
	assert.Equal(t, core.MediaShow, hits[0].Type)
	assert.Equal(t, "false", urlQuery(stub.first(t).URL).Get("include_adult"))
}

func TestTMDBNewShowsWindow(t *testing.T) {
	stub := routes(map[string]string{"/discover/tv": `{"results":[]}`})
	_, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}).List(context.Background(), ListTVNew, discoverNow)
	require.NoError(t, err)
	q := urlQuery(stub.first(t).URL)
	assert.Equal(t, "2026-07-22", q.Get("first_air_date.gte"))
	assert.Equal(t, "2026-10-20", q.Get("first_air_date.lte"))
	assert.Equal(t, "popularity.desc", q.Get("sort_by"))
}

func TestTMDBMovieRowsKeepMovies(t *testing.T) {
	stub := routes(map[string]string{"/movie/now_playing": `{"results":[{"id":9,"title":"Film","release_date":"2026-10-01",
	  "poster_path":"/f.jpg","genre_ids":[16],"original_language":"ja"}]}`})
	hits, err := (&TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}).List(context.Background(), ListMoviesInTheaters, discoverNow)
	require.NoError(t, err)
	require.Len(t, hits, 1)
	assert.Equal(t, "9", hits[0].IDs.TMDB)
	assert.Equal(t, core.MediaMovie, hits[0].Type)
}

func TestAniListSeasonRow(t *testing.T) {
	stub := routes(map[string]string{"": `{"data":{"Page":{"media":[
	  {"id":195516,"idMal":1,"format":"TV","status":"RELEASING","title":{"english":"Apothecary Diaries"},
	   "startDate":{"year":2026},"coverImage":{"large":"https://img/a.jpg"}}]}}}`})
	hits, err := (&AniList{Client: testClient(stub, "anilist")}).List(context.Background(), ListAnimeSeason, discoverNow)
	require.NoError(t, err)
	require.Len(t, hits, 1)
	assert.Equal(t, "195516", hits[0].IDs.AniList)
	assert.True(t, hits[0].IsAnime)
	body := string(stub.first(t).Body)
	assert.Contains(t, body, "season: FALL, seasonYear: 2026, sort: POPULARITY_DESC")
	assert.Contains(t, body, "isAdult: false")
}

func TestAniListMangaRows(t *testing.T) {
	stub := routes(map[string]string{"": `{"data":{"Page":{"media":[
	  {"id":30013,"idMal":13,"type":"MANGA","format":"MANGA","status":"RELEASING","title":{"english":"One Piece"},
	   "startDate":{"year":1997},"coverImage":{"large":"https://img/m.jpg"}}]}}}`})
	catalog := &AniList{Client: testClient(stub, "anilist")}
	trending, err := catalog.List(context.Background(), ListMangaTrending, discoverNow)
	require.NoError(t, err)
	require.Len(t, trending, 1)
	assert.Equal(t, core.MediaManga, trending[0].Type)
	assert.False(t, trending[0].IsAnime)
	_, err = catalog.List(context.Background(), ListMangaPublishing, discoverNow)
	require.NoError(t, err)
	reqs := stub.all()
	require.Len(t, reqs, 2)
	for _, r := range reqs {
		assert.Contains(t, string(r.Body), "type: MANGA, isAdult: false, status: RELEASING")
	}
	assert.Contains(t, string(reqs[0].Body), "sort: TRENDING_DESC")
	assert.Contains(t, string(reqs[1].Body), "sort: POPULARITY_DESC")
}

func TestRowKinds(t *testing.T) {
	assert.Equal(t, RowShow, ListTVTrending.Kind())
	assert.Equal(t, RowFilm, ListMoviesInTheaters.Kind())
	assert.Equal(t, RowAnime, ListAnimeTrending.Kind())
	assert.Equal(t, RowBook, ListBooksTrending.Kind())
	assert.Equal(t, RowManga, ListMangaPublishing.Kind())
	assert.Equal(t, RowAlbum, ListMusicUpcoming.Kind())
}

func TestOpenLibraryTrending(t *testing.T) {
	stub := routes(map[string]string{"/trending/weekly.json": `{"works":[{"key":"/works/OL17930368W","title":"Atomic Habits",
	  "author_name":["James Clear"],"first_publish_year":2016,"cover_i":12539702}]}`})
	hits, err := (&OpenLibrary{Client: testClient(stub, "openlibrary"), UserAgent: "test"}).List(context.Background(), ListBooksTrending, discoverNow)
	require.NoError(t, err)
	require.Len(t, hits, 1)
	assert.Equal(t, "OL17930368W", hits[0].IDs.OpenLibrary)
	assert.Equal(t, "James Clear", *hits[0].Byline)
	assert.Equal(t, "https://covers.openlibrary.org/b/id/12539702-L.jpg", *hits[0].PosterURL)
}

func TestSeasonFollowsTheUTCQuarter(t *testing.T) {
	for instant, expected := range map[string]SeasonOfYear{
		"2026-01-01T00:00:00Z": Winter, "2026-03-31T23:59:59Z": Winter, "2026-04-01T00:00:00Z": Spring,
		"2026-07-01T00:00:00Z": Summer, "2026-09-30T23:59:59Z": Summer, "2026-10-01T00:00:00Z": Fall,
		"2026-12-31T23:59:59Z": Fall,
	} {
		at, err := time.Parse(time.RFC3339, instant)
		require.NoError(t, err)
		assert.Equal(t, SeasonKey{Season: expected, Year: 2026}, CurrentSeason(at), instant)
	}
	assert.Equal(t, "Fall 2026 anime", ListAnimeSeason.Title(discoverNow))
}

// MARK: Cache

func cacheGet(c *sharedCache[DiscoverList, discoverFetch], list DiscoverList, now time.Time, fetch func(context.Context) (discoverFetch, error)) (discoverFetch, bool) {
	return c.get(context.Background(), list, now, func(f discoverFetch) time.Duration { return f.ttl }, fetch)
}

func TestCacheServesUntilTheTTL(t *testing.T) {
	cache := newSharedCache[DiscoverList, discoverFetch](0, "test")
	var calls atomic.Int32
	fetch := func(context.Context) (discoverFetch, error) {
		calls.Add(1)
		return discoverFetch{hits: []Hit{discoverHit("A", core.MediaMovie, "1", true)}, ttl: DiscoverTTL}, nil
	}
	cacheGet(cache, ListMoviesTrending, discoverNow, fetch)
	cacheGet(cache, ListMoviesTrending, discoverNow.Add(time.Minute), fetch)
	assert.Equal(t, int32(1), calls.Load())
	cacheGet(cache, ListMoviesTrending, discoverNow.Add(DiscoverTTL), fetch)
	assert.Equal(t, int32(2), calls.Load())
}

func TestCacheCoalescesConcurrentCallers(t *testing.T) {
	cache := newSharedCache[DiscoverList, discoverFetch](0, "test")
	var calls atomic.Int32
	fetch := func(context.Context) (discoverFetch, error) {
		calls.Add(1)
		time.Sleep(30 * time.Millisecond)
		return discoverFetch{hits: []Hit{discoverHit("A", core.MediaMovie, "1", true)}, ttl: DiscoverTTL}, nil
	}
	results := make(chan int, 2)
	for range 2 {
		go func() {
			f, _ := cacheGet(cache, ListTVTrending, discoverNow, fetch)
			results <- len(f.hits)
		}()
	}
	assert.Equal(t, 1, <-results)
	assert.Equal(t, 1, <-results)
	assert.Equal(t, int32(1), calls.Load())
}

func TestCacheServesStaleOnFailureAndBacksOff(t *testing.T) {
	cache := newSharedCache[DiscoverList, discoverFetch](0, "test")
	cacheGet(cache, ListBooksTrending, discoverNow, func(context.Context) (discoverFetch, error) {
		return discoverFetch{hits: []Hit{discoverHit("Old", core.MediaBook, "1", true)}, ttl: DiscoverTTL}, nil
	})
	var calls atomic.Int32
	failing := func(context.Context) (discoverFetch, error) {
		calls.Add(1)
		return discoverFetch{}, provider.NewError("openlibrary", provider.KindUnavailable)
	}
	stale := discoverNow.Add(DiscoverTTL)
	served, ok := cacheGet(cache, ListBooksTrending, stale, failing)
	require.True(t, ok)
	assert.Equal(t, []string{"Old"}, titlesOf(served.hits))
	_, ok = cacheGet(cache, ListBooksTrending, stale.Add(time.Minute), failing)
	assert.True(t, ok)
	assert.Equal(t, int32(1), calls.Load())
	cacheGet(cache, ListBooksTrending, stale.Add(DiscoverRetryAfter), failing)
	assert.Equal(t, int32(2), calls.Load())
}

// MARK: Service

// halfBroken serves two lists; one always fails.
type halfBroken struct{}

func (halfBroken) DiscoverLists() []DiscoverList {
	return []DiscoverList{ListTVTrending, ListMoviesTrending}
}

func (halfBroken) List(_ context.Context, list DiscoverList, _ time.Time) ([]Hit, error) {
	if list != ListMoviesTrending {
		return nil, provider.NewError("tmdb", provider.KindUnavailable)
	}
	return []Hit{discoverHit("Film", core.MediaMovie, "1", true)}, nil
}

// downAniList answers "disabled".
type downAniList struct{}

func (downAniList) DiscoverLists() []DiscoverList {
	return []DiscoverList{ListAnimeSeason, ListAnimeTrending, ListMangaTrending, ListMangaPublishing}
}

func (downAniList) List(context.Context, DiscoverList, time.Time) ([]Hit, error) {
	return nil, provider.NewError("anilist", provider.KindUnavailable)
}

type animeStandIn struct{}

func (animeStandIn) DiscoverLists() []DiscoverList { return nil }

func (animeStandIn) List(_ context.Context, list DiscoverList, _ time.Time) ([]Hit, error) {
	h := discoverHit("Frieren "+string(list), core.MediaShow, "209867", true)
	h.IsAnime = true
	return []Hit{h}, nil
}

func rowLists(rows []DiscoverRow) []DiscoverList {
	out := []DiscoverList{}
	for _, r := range rows {
		out = append(out, r.List)
	}
	return out
}

func TestFailingProviderDropsItsOwnRowOnly(t *testing.T) {
	service := NewDiscoverService(NewStore(testdb.New(t)), []any{halfBroken{}}, nil, nil, nil)
	rows, err := service.Rows(context.Background(), uuid.New())
	require.NoError(t, err)
	assert.Equal(t, []DiscoverList{ListMoviesTrending}, rowLists(rows))
}

func TestAniListOutageFallsBackToTMDBAnime(t *testing.T) {
	service := NewDiscoverService(NewStore(testdb.New(t)), []any{downAniList{}}, animeStandIn{}, nil, nil)
	rows, err := service.Rows(context.Background(), uuid.New())
	require.NoError(t, err)
	// Manga has no stand-in: its rows are absent while AniList is down.
	assert.ElementsMatch(t, []DiscoverList{ListAnimeSeason, ListAnimeTrending}, rowLists(rows))
	for _, r := range rows {
		assert.Equal(t, AnimeFallbackNote, *r.Note)
		for _, item := range r.Items {
			assert.True(t, item.Hit.IsAnime)
		}
	}

	cache := newSharedCache[DiscoverList, discoverFetch](0, "test")
	var calls atomic.Int32
	fetch := func(context.Context) (discoverFetch, error) {
		calls.Add(1)
		return discoverFetch{hits: []Hit{discoverHit("A", core.MediaMovie, "1", true)}, ttl: FallbackTTL}, nil
	}
	cacheGet(cache, ListAnimeSeason, discoverNow, fetch)
	cacheGet(cache, ListAnimeSeason, discoverNow.Add(time.Minute), fetch)
	cacheGet(cache, ListAnimeSeason, discoverNow.Add(FallbackTTL), fetch)
	assert.Equal(t, int32(2), calls.Load(), "a stand-in row is asked for again after 30 minutes, not 6 hours")
}

func TestTMDBAnimeStandInQuery(t *testing.T) {
	season, err := tmdbAnimeQuery(ListAnimeSeason, discoverNow)
	require.NoError(t, err)
	assert.Equal(t, "16", season["with_genres"])
	assert.Equal(t, "JP", season["with_origin_country"])
	assert.Equal(t, "2026-10-01", season["first_air_date.gte"])
	assert.Equal(t, "2026-12-31", season["first_air_date.lte"])
	trending, err := tmdbAnimeQuery(ListAnimeTrending, discoverNow)
	require.NoError(t, err)
	assert.Equal(t, "2026-10-13", trending["air_date.gte"])
	assert.Equal(t, "2026-10-27", trending["air_date.lte"])
}

func TestDiscoverMarksTheLibraryAndDropsPosterless(t *testing.T) {
	env := newRefreshEnv(t)
	owned := env.title(core.MediaMovie, "Owned", core.ExternalIDs{TMDB: "4242"})
	var itemID uuid.UUID
	env.track(owned.ID, "wishlist")
	require.NoError(t, env.pool.QueryRow(env.ctx, `SELECT id FROM library_items WHERE title_id = $1`, owned.ID).Scan(&itemID))
	fake := newFake()
	fake.stubDiscover(ListMoviesTrending, []Hit{discoverHit("Owned", core.MediaMovie, "4242", true), discoverHit("New", core.MediaMovie, "x-1", true)})
	// Same TMDB number, other type: never the owned movie.
	fake.stubDiscover(ListTVTrending, []Hit{discoverHit("Show", core.MediaShow, "4242", true)})
	fake.stubDiscover(ListBooksTrending, []Hit{discoverHit("No cover", core.MediaBook, "b", false)})
	service := NewDiscoverService(env.store, []any{fake}, nil, nil, nil)
	rows, err := service.Rows(env.ctx, env.user)
	require.NoError(t, err)
	assert.Equal(t, []DiscoverList{ListTVTrending, ListMoviesTrending}, rowLists(rows))
	require.Len(t, rows[1].Items, 2)
	assert.Equal(t, itemID, *rows[1].Items[0].LibraryItemID)
	assert.Nil(t, rows[1].Items[1].LibraryItemID)
	assert.Nil(t, rows[0].Items[0].LibraryItemID)
}
