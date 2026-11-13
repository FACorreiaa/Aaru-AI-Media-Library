package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/testdb"
	"context"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// The adult rule (CAT-023, adult.go): no list offers a work its provider marks adult, a read by
// id still answers, and the resolver makes no new title of one. Canned JSON, no network.

const aniListAdultPage = `{"data":{"Page":{"pageInfo":{"hasNextPage":false,"total":2},"media":[
 {"id":1,"idMal":11,"type":"ANIME","format":"TV","isAdult":false,"title":{"english":"Safe"},"startDate":{"year":2020}},
 {"id":2,"idMal":12,"type":"ANIME","format":"OVA","isAdult":true,"title":{"english":"Adult"},"startDate":{"year":2021}}]}}}`

func hitTitles(hits []Hit) []string {
	titles := make([]string, len(hits))
	for i, h := range hits {
		titles[i] = h.Title
	}
	return titles
}

func TestAniListSearchAsksForNoAdultWorksAndDropsAnyThatCome(t *testing.T) {
	for _, mediaType := range []core.MediaType{core.MediaShow, core.MediaManga} {
		anilist, stub := aniListWith(aniListAdultPage)
		hits, err := anilist.Search(context.Background(), "x", mediaType)
		require.NoError(t, err)
		assert.Equal(t, []string{"Safe"}, hitTitles(hits), string(mediaType))
		body := string(stub.first(t).Body)
		assert.Contains(t, body, "type: "+aniListType(mediaType)+", isAdult: false", "anime search filters as manga search does")
		assert.Contains(t, body, "status isAdult", "each entry is read with AniList's mark")
	}
}

func TestAniListRowsSeasonsAndPopularDropAdultWorks(t *testing.T) {
	ctx, now := context.Background(), time.Date(2026, 11, 13, 0, 0, 0, 0, time.UTC)
	for _, list := range []DiscoverList{ListAnimeSeason, ListAnimeTrending, ListMangaTrending, ListMangaPublishing} {
		anilist, stub := aniListWith(aniListAdultPage)
		hits, err := anilist.List(ctx, list, now)
		require.NoError(t, err)
		assert.Equal(t, []string{"Safe"}, hitTitles(hits), string(list))
		assert.Contains(t, string(stub.first(t).Body), "isAdult: false", string(list))
	}
	anilist, stub := aniListWith(aniListAdultPage)
	season, err := anilist.Season(ctx, SeasonKey{Season: Fall, Year: 2026}, SeasonAnime, 1, now)
	require.NoError(t, err)
	assert.Equal(t, []string{"Safe"}, hitTitles(season.Hits))
	assert.Contains(t, string(stub.first(t).Body), "isAdult: false")
	for _, kind := range []RowKind{RowAnime, RowManga} {
		anilist, stub := aniListWith(aniListAdultPage)
		hits, err := anilist.Popular(ctx, kind, OnboardingGenre{})
		require.NoError(t, err)
		assert.Equal(t, []string{"Safe"}, hitTitles(hits))
		assert.Contains(t, string(stub.first(t).Body), "isAdult: false")
	}
}

func TestAniListReadsByIDAnswerForAnAdultWorkAndMarkIt(t *testing.T) {
	ctx := context.Background()
	anilist, _ := aniListWith(`{"data":{"Media":{"id":2,"idMal":12,"type":"ANIME","format":"OVA","isAdult":true,
	  "title":{"english":"Adult"},"startDate":{"year":2021}}}}`)
	record, err := anilist.Hydrate(ctx, core.ExternalIDs{AniList: "2"}, core.MediaShow)
	require.NoError(t, err)
	require.NotNil(t, record, "a title already held still refreshes")
	assert.True(t, record.Hit.Adult)

	anilist, _ = aniListWith(aniListAdultPage)
	found, err := anilist.HydrateMAL(ctx, []string{"11", "12"}, core.MediaShow)
	require.NoError(t, err)
	require.Len(t, found, 2, "an adult entry is known, not unknown")
	assert.False(t, found["11"].Hit.Adult)
	assert.True(t, found["12"].Hit.Adult)
}

func TestAniListRelationsLeaveAdultWorksOut(t *testing.T) {
	anilist, stub := aniListWith(`{"data":{"Media":{"id":1,"type":"ANIME","format":"TV","title":{"english":"Safe"},
"relations":{"edges":[
 {"relationType":"SEQUEL","node":{"id":3,"type":"ANIME","format":"TV","isAdult":false,"title":{"english":"Safe 2"}}},
 {"relationType":"SIDE_STORY","node":{"id":2,"type":"ANIME","format":"OVA","isAdult":true,"title":{"english":"Adult"}}}]}}}}`)
	r, err := anilist.Relations(context.Background(), RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{AniList: "1"}})
	require.NoError(t, err)
	require.Len(t, r.Edges, 1)
	assert.Equal(t, "Safe 2", r.Edges[0].To.Title)
	assert.Contains(t, string(stub.first(t).Body), "format isAdult")
}

func TestAniListListEntriesCarryTheAdultMark(t *testing.T) {
	anilist, stub := aniListWith(`{"data":{"MediaListCollection":{"lists":[{"entries":[
 {"status":"CURRENT","media":{"id":1,"format":"TV","isAdult":false,"title":{"english":"Safe"}}},
 {"status":"COMPLETED","media":{"id":2,"format":"OVA","isAdult":true,"title":{"english":"Adult"}}}]}]}}}`)
	entries, err := anilist.listEntries(context.Background(), "someone", core.MediaShow)
	require.NoError(t, err)
	require.Len(t, entries, 2, "the import counts the adult entry, it does not lose it")
	assert.False(t, entries[0].Adult)
	assert.True(t, entries[1].Adult)
	assert.Contains(t, string(stub.first(t).Body), "format isAdult")
}

// tmdbAdultStub answers every TMDB list with one safe and one adult entry, and by id for film 2.
func tmdbAdultStub() (*TMDB, *stubTransport) {
	const entries = `{"id":1,"media_type":"movie","title":"Safe","name":"Safe","release_date":"2020-01-01","first_air_date":"2020-01-01","adult":false,"job":"Director"},
 {"id":2,"media_type":"movie","title":"Adult","name":"Adult","release_date":"2021-01-01","first_air_date":"2021-01-01","adult":true,"job":"Director"}`
	stub := stubFunc(func(req provider.Request) provider.Response {
		path := strings.TrimPrefix(urlPath(req.URL), "/3")
		switch {
		case path == "/movie/1":
			return provider.Response{Status: 200, Body: []byte(`{"id":1,"title":"Safe","belongs_to_collection":{"id":10}}`)}
		case path == "/movie/2":
			return provider.Response{Status: 200, Body: []byte(`{"id":2,"title":"Adult","release_date":"2021-01-01","adult":true}`)}
		case path == "/collection/10":
			return provider.Response{Status: 200, Body: []byte(`{"parts":[` + entries + `]}`)}
		case strings.HasPrefix(path, "/person/"):
			return provider.Response{Status: 200, Body: []byte(`{"crew":[` + entries + `],"cast":[]}`)}
		case strings.HasSuffix(path, "/external_ids"):
			return provider.Response{Status: 200, Body: []byte(`{}`)}
		}
		return provider.Response{Status: 200, Body: []byte(`{"results":[` + entries + `],"total_pages":1}`)}
	})
	return &TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}, stub
}

func TestTMDBListsDropAdultTitles(t *testing.T) {
	ctx, now := context.Background(), time.Date(2026, 11, 13, 0, 0, 0, 0, time.UTC)
	tmdb, stub := tmdbAdultStub()

	hits, err := tmdb.Search(ctx, "x", core.MediaMovie)
	require.NoError(t, err)
	assert.Equal(t, []string{"Safe"}, hitTitles(hits))
	assert.Equal(t, "false", urlQuery(stub.first(t).URL).Get("include_adult"))

	hits, err = tmdb.SearchMulti(ctx, "x")
	require.NoError(t, err)
	assert.Equal(t, []string{"Safe"}, hitTitles(hits))

	// Trending, now playing and on the air take no `include_adult`: the mark alone filters them.
	for _, list := range []DiscoverList{
		ListTVTrending, ListTVOnAir, ListTVNew, ListMoviesTrending, ListMoviesInTheaters, ListAnimeSeason, ListAnimeTrending,
	} {
		hits, err = tmdb.List(ctx, list, now)
		require.NoError(t, err)
		assert.Equal(t, []string{"Safe"}, hitTitles(hits), string(list))
	}
	hits, _, err = tmdb.onAirPage(ctx, 1)
	require.NoError(t, err)
	assert.Empty(t, hits, "no poster, no card; and the adult one is not a card either")

	for _, kind := range []SeasonKind{SeasonShowsNew, SeasonShowsReturning, SeasonMovies} {
		page, err := tmdb.Season(ctx, SeasonKey{Season: Fall, Year: 2026}, kind, 1, now)
		require.NoError(t, err)
		assert.Equal(t, []string{"Safe"}, hitTitles(page.Hits), string(kind))
	}
	for _, kind := range []RowKind{RowFilm, RowShow, RowAnime} {
		hits, err = tmdb.Popular(ctx, kind, OnboardingGenre{})
		require.NoError(t, err)
		assert.Equal(t, []string{"Safe"}, hitTitles(hits))
	}
	for _, req := range stub.all() {
		path := urlPath(req.URL)
		if strings.Contains(path, "/search/") || strings.Contains(path, "/discover/") {
			assert.Equal(t, "false", urlQuery(req.URL).Get("include_adult"), path)
		}
	}
}

func TestTMDBCollectionsAndCreditsDropAdultTitles(t *testing.T) {
	ctx := context.Background()
	tmdb, _ := tmdbAdultStub()
	r, err := tmdb.Relations(ctx, RelatedNode{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: "1"}})
	require.NoError(t, err)
	assert.Empty(t, r.Edges, "the collection's adult part is no part: one film is no chain")

	works, err := tmdb.Works(ctx, Credit{Kind: core.BranchDirector, ID: "7", Name: "A Director"})
	require.NoError(t, err)
	require.Len(t, works, 1)
	assert.Equal(t, "Safe", works[0].Title)
}

func TestTMDBReadByIDAnswersForAnAdultTitleAndMarksIt(t *testing.T) {
	tmdb, _ := tmdbAdultStub()
	record, err := tmdb.Hydrate(context.Background(), core.ExternalIDs{TMDB: "2"}, core.MediaMovie)
	require.NoError(t, err)
	require.NotNil(t, record, "a title already held still refreshes")
	assert.True(t, record.Hit.Adult)
}

func TestWikidataLeavesOutWhatTMDBMarksAdult(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		q := urlQuery(req.URL)
		switch {
		case q.Get("action") == "query":
			return provider.Response{Status: 200, Body: []byte(`{"query":{"search":[{"title":"Q1"}]}}`)}
		case q.Get("ids") == "Q1":
			return provider.Response{Status: 200, Body: []byte(`{"entities":{"Q1":{"labels":{"en":{"value":"Safe"}},"claims":{
"P156":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q2"}}}}],
"P155":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q3"}}}}]}}}}`)}
		}
		return provider.Response{Status: 200, Body: []byte(`{"entities":{
"Q2":{"labels":{"en":{"value":"Adult"}},"claims":{"P31":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q11424"}}}}],"P4947":[{"rank":"normal","mainsnak":{"datavalue":{"value":"2"}}}]}},
"Q3":{"labels":{"en":{"value":"Before"}},"claims":{"P31":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q11424"}}}}],"P4947":[{"rank":"normal","mainsnak":{"datavalue":{"value":"3"}}}]}}}}`)}
	})
	fake := newFake()
	adult := movieRecord("Adult", 2021, core.ExternalIDs{TMDB: "2"})
	adult.Hit.Adult = true
	fake.stubTitle(adult)
	fake.stubTitle(movieRecord("Before", 2019, core.ExternalIDs{TMDB: "3"}))
	w := &Wikidata{Client: testClient(stub, "wikidata"), Enrich: TMDBRelatedEnricher(fake)}
	r, err := w.Relations(context.Background(), RelatedNode{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: "1"}})
	require.NoError(t, err)
	require.Len(t, r.Edges, 1)
	assert.Equal(t, "Before", r.Edges[0].To.Title)
}

// The resolver is the one door a new title comes through.
func TestResolverMakesNoTitleOfAnAdultWorkAndKeepsOneAlreadyHeld(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	store := NewStore(pool)
	fake := newFake()
	fresh, held := "9"+uuid.NewString()[:7], "8"+uuid.NewString()[:7]
	for _, id := range []string{fresh, held} {
		record := movieRecord("Adult "+id, 2021, core.ExternalIDs{TMDB: id})
		record.Hit.Adult = true
		fake.stubTitle(record)
	}
	resolver := NewResolver(store, fake.providers())

	_, err := resolver.Resolve(ctx, core.MediaRef{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: fresh}}, nil)
	re, ok := IsResolutionError(err)
	require.True(t, ok, "an import counts it as unmatched, never a failed job")
	assert.Equal(t, ErrAdult, re)
	assert.Equal(t, "unresolvable", re.AppError().Code)
	assert.Equal(t, AdultReason, re.AppError().Message)
	var rows int
	require.NoError(t, pool.QueryRow(ctx, `SELECT count(*) FROM titles WHERE tmdb = $1`, fresh).Scan(&rows))
	assert.Zero(t, rows)

	// A title someone already has: found by its id, read again, never removed.
	year := 2021
	existing := core.Title{ID: uuid.New(), Type: core.MediaMovie, Title: "Adult " + held, Year: &year, IDs: core.ExternalIDs{TMDB: held}}
	require.NoError(t, store.Insert(ctx, existing, nil, nil, nil))
	got, err := resolver.Resolve(ctx, core.MediaRef{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: held}}, nil)
	require.NoError(t, err)
	assert.Equal(t, existing.ID, got.ID)
	record, err := resolver.Hydrate(ctx, existing.IDs, core.MediaMovie)
	require.NoError(t, err)
	require.NotNil(t, record, "its refresh still reads the provider")
	detail, err := NewService(store, fake.providers()).Detail(ctx, existing.ID)
	require.NoError(t, err)
	require.NotNil(t, detail)
}
