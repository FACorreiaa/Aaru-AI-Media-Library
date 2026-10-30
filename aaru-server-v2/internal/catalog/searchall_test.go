package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/testdb"
	"context"
	"strconv"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// CAT-019: the All scope over separate TMDB, AniList and Open Library fakes.

type searchFakes struct{ tmdb, anilist, openLibrary *fakeCatalog }

func newSearchFakes() searchFakes { return searchFakes{newFake(), newFake(), newFake()} }

func (f searchFakes) providers() Providers {
	return Providers{TMDB: f.tmdb, AniList: f.anilist, OpenLibrary: f.openLibrary}
}

func searchHit(title string, mediaType core.MediaType, ids core.ExternalIDs, anime bool) Hit {
	return Hit{Type: mediaType, Title: title, Year: ptr(2025), IDs: ids, IsAnime: anime}
}

func titlesOf(hits []Hit) []string {
	out := []string{}
	for _, h := range hits {
		out = append(out, h.Title)
	}
	return out
}

func TestSearchAllMixesKindsExactFirst(t *testing.T) {
	f := newSearchFakes()
	mobland := searchHit("MobLand", core.MediaShow, core.ExternalIDs{TMDB: "2"}, false)
	f.tmdb.stubSearch("Mobland", []Hit{searchHit("Mob Land Stories", core.MediaMovie, core.ExternalIDs{TMDB: "1"}, false), mobland})
	f.anilist.stubSearch("Mobland", []Hit{searchHit("Mobland Gakuen", core.MediaShow, core.ExternalIDs{AniList: "3"}, true)})
	f.openLibrary.stubSearch("Mobland", []Hit{searchHit("Mobland", core.MediaBook, core.ExternalIDs{ISBN: "1"}, false)})
	service := NewService(NewStore(testdb.New(t)), f.providers())
	result, err := service.Search(context.Background(), "Mobland", ScopeAll)
	require.NoError(t, err)
	assert.Equal(t, mobland, result.Hits[0], "the exact title leads")
	assert.Equal(t, []string{"MobLand", "Mob Land Stories", "Mobland Gakuen"}, titlesOf(result.Hits))
	assert.False(t, result.Incomplete)
	assert.Equal(t, 0, f.openLibrary.callCount("search"))
	assert.Equal(t, 1, f.tmdb.callCount("searchMulti"))
	assert.Equal(t, 0, f.tmdb.callCount("search"))
}

func TestSearchAllDedupesOnlyThroughMappings(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	require.NoError(t, store.UpsertMapping(ctx, AnimeMapping{AniList: "154587", TMDB: ptr("209867"), TMDBSeason: ptr(1)}))
	f := newSearchFakes()
	sameName := core.ExternalIDs{TMDB: "5"}
	f.tmdb.stubSearch("frieren", []Hit{
		searchHit("Frieren", core.MediaShow, core.ExternalIDs{TMDB: "209867"}, true),
		// Same name, no shared id: a different work as far as Aaru knows.
		searchHit("Frieren", core.MediaMovie, sameName, false),
	})
	f.anilist.stubSearch("frieren", []Hit{
		searchHit("Frieren", core.MediaShow, core.ExternalIDs{AniList: "154587"}, true),
		searchHit("Frieren", core.MediaShow, core.ExternalIDs{AniList: "999"}, true),
	})
	result, err := NewService(store, f.providers()).Search(ctx, "frieren", ScopeAll)
	require.NoError(t, err)
	hits := result.Hits
	assert.Len(t, hits, 3)
	var mapped []string
	withAniList := 0
	foundSameName := false
	for _, h := range hits {
		if h.IDs.TMDB == "209867" {
			mapped = append(mapped, h.IDs.AniList)
		}
		if h.IDs.AniList != "" {
			withAniList++
		}
		foundSameName = foundSameName || h.IDs == sameName
	}
	assert.Equal(t, []string{"154587"}, mapped, "kept once, as AniList")
	assert.True(t, foundSameName)
	assert.Equal(t, 2, withAniList)
}

func TestAnimeSearchStandsInWhileAniListIsDown(t *testing.T) {
	f := newSearchFakes()
	f.tmdb.stubSearch("frieren", []Hit{
		searchHit("Frieren", core.MediaShow, core.ExternalIDs{TMDB: "1"}, true),
		searchHit("Frieren: The Documentary", core.MediaMovie, core.ExternalIDs{TMDB: "2"}, false),
	})
	f.anilist.fail(provider.NewError("anilist", provider.KindUnavailable))
	service := NewService(NewStore(testdb.New(t)), f.providers())
	result, err := service.Search(context.Background(), "frieren", ScopeAnime)
	require.NoError(t, err)
	assert.Equal(t, []string{"Frieren"}, titlesOf(result.Hits), "anime only")
	assert.True(t, result.Incomplete)
	assert.Equal(t, NoticeAniListDown, *result.Notice)
	all, err := service.Search(context.Background(), "frieren", ScopeAll)
	require.NoError(t, err)
	assert.Equal(t, NoticeAniListDown, *all.Notice)
}

func TestSearchAllAnswersWithWhatArrived(t *testing.T) {
	ctx := context.Background()
	f := newSearchFakes()
	f.tmdb.stubSearch("dune", []Hit{searchHit("Dune", core.MediaMovie, core.ExternalIDs{TMDB: "1"}, false)})
	f.anilist.stubSearch("dune", []Hit{searchHit("Dune Gakuen", core.MediaShow, core.ExternalIDs{AniList: "1"}, true)})
	service := NewService(NewStore(testdb.New(t)), f.providers())
	service.AniListDeadline = 50 * time.Millisecond

	f.anilist.fail(provider.NewError("anilist", provider.KindUnavailable))
	result, err := service.Search(ctx, "dune", ScopeAll)
	require.NoError(t, err)
	assert.True(t, result.Incomplete)
	assert.Equal(t, []string{"Dune"}, titlesOf(result.Hits))

	f.anilist.fail(nil)
	f.anilist.delay(5 * time.Second)
	started := time.Now()
	result, err = service.Search(ctx, "dune", ScopeAll)
	require.NoError(t, err)
	assert.True(t, result.Incomplete)
	assert.Equal(t, []string{"Dune"}, titlesOf(result.Hits))
	assert.Less(t, time.Since(started), 2*time.Second, "AniList's deadline, not its latency")

	f.anilist.delay(0)
	f.tmdb.fail(provider.NewError("tmdb", provider.KindUnavailable))
	result, err = service.Search(ctx, "dune", ScopeAll)
	require.NoError(t, err)
	assert.True(t, result.Incomplete)
	assert.Equal(t, []string{"Dune Gakuen"}, titlesOf(result.Hits))

	f.anilist.fail(provider.NewError("anilist", provider.KindUnavailable))
	_, err = service.Search(ctx, "dune", ScopeAll)
	assert.ErrorIs(t, err, provider.NewError("tmdb", provider.KindUnavailable))
}

func TestRankedAlternatesAfterExactAndStopsAt40(t *testing.T) {
	var video, anime []Hit
	for i := range 30 {
		n := strconv.Itoa(i)
		video = append(video, searchHit("Video "+n, core.MediaMovie, core.ExternalIDs{TMDB: n}, false))
		anime = append(anime, searchHit("Anime "+n, core.MediaShow, core.ExternalIDs{AniList: n}, true))
	}
	exact := searchHit("The Exact One", core.MediaShow, core.ExternalIDs{AniList: "x"}, true)
	ranked := Ranked(video, append(anime, exact), "exact one")
	assert.Len(t, ranked, AllLimit)
	assert.Equal(t, exact, ranked[0], "a leading article and case do not matter")
	assert.Equal(t, []string{"Video 0", "Anime 0", "Video 1", "Anime 1"}, titlesOf(ranked[1:5]))
}

func TestSearchValidatesLength(t *testing.T) {
	service := NewService(nil, newSearchFakes().providers())
	_, err := service.Search(context.Background(), "   ", ScopeMovie)
	require.Error(t, err)
	assert.Equal(t, ErrSearchLength(), err)
}
