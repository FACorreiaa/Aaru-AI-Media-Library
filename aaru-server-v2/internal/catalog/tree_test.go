package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/testdb"
	"context"
	"errors"
	"log/slog"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GRAPH-005: the credit cache and a person's branch, against the database.

func TestCreditCacheServesFreshAnswersAndTheOldOneWhenAFetchFails(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	now := time.Date(2026, 11, 11, 12, 0, 0, 0, time.UTC)
	cache := creditCache{q: store.q, now: func() time.Time { return now }, log: slog.Default()}
	fetches := 0
	director := []Credit{{Kind: core.BranchDirector, ID: "137427", Name: "Denis Villeneuve"}}
	fetch := func(context.Context) ([]Credit, error) { fetches++; return director, nil }
	failing := func(context.Context) ([]Credit, error) { fetches++; return nil, errors.New("provider down") }
	key := "title:movie:" + randomID()

	got, err := cachedCredits(ctx, cache, "tmdb", key, fetch)
	require.NoError(t, err)
	assert.Equal(t, director, got)
	now = now.Add(29 * 24 * time.Hour)
	got, err = cachedCredits(ctx, cache, "tmdb", key, failing)
	require.NoError(t, err)
	assert.Equal(t, director, got)
	assert.Equal(t, 1, fetches, "a month-old answer is still read from the cache")

	now = now.Add(2 * 24 * time.Hour)
	got, err = cachedCredits(ctx, cache, "tmdb", key, failing)
	require.NoError(t, err, "a failed fetch serves the old answer")
	assert.Equal(t, director, got)
	assert.Equal(t, 2, fetches)

	// "Nobody found" is believed for a day only.
	empty := "title:movie:" + randomID()
	none := func(context.Context) ([]Credit, error) { fetches++; return nil, nil }
	got, err = cachedCredits(ctx, cache, "tmdb", empty, none)
	require.NoError(t, err)
	assert.Empty(t, got)
	now = now.Add(23 * time.Hour)
	_, err = cachedCredits(ctx, cache, "tmdb", empty, none)
	require.NoError(t, err)
	assert.Equal(t, 3, fetches)
	now = now.Add(2 * time.Hour)
	_, err = cachedCredits(ctx, cache, "tmdb", empty, none)
	require.NoError(t, err)
	assert.Equal(t, 4, fetches, "asked again after a day")

	_, err = cachedCredits(ctx, cache, "tmdb", "title:movie:"+randomID(), failing)
	require.Error(t, err, "nothing cached and the provider is down")
}

// A studio's branch holds one title per show: AniList lists each season on its own.
func TestPersonBranchFoldsAnAnimesSeasonsAndDropsTheRootsOwn(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	rootShow, otherShow := randomID(), randomID()
	root1, root2, other1, other2, filmID, lone := randomID(), randomID(), randomID(), randomID(), randomID(), randomID()
	season := func(n int) *int { return &n }
	require.NoError(t, store.UpsertMappings(ctx, []AnimeMapping{
		{AniList: root1, TMDB: &rootShow, TMDBSeason: season(1)},
		{AniList: root2, TMDB: &rootShow, TMDBSeason: season(2)},
		{AniList: other1, TMDB: &otherShow, TMDBSeason: season(1)},
		{AniList: other2, TMDB: &otherShow, TMDBSeason: season(2)},
	}))
	anime := func(id, title, date string, mediaType core.MediaType, score int) CreditedWork {
		return CreditedWork{Score: score, RelatedNode: RelatedNode{
			Type: mediaType, IsAnime: true, IDs: core.ExternalIDs{AniList: id}, Title: title, ReleaseDate: &date,
		}}
	}
	service := NewTreeService(NewRelationService(store, nil, nil), nil, nil)
	centre := RelatedNode{Type: core.MediaShow, IsAnime: true, IDs: core.ExternalIDs{TMDB: rootShow, AniList: root1}, Title: "Root"}
	branch, ok := service.personBranch(ctx, centre, RelationGraph{}, credited{
		credit: Credit{Kind: core.BranchStudio, ID: "858", Name: "WIT STUDIO"},
		works: []CreditedWork{
			anime(root1, "Root", "2013-04-07", core.MediaShow, 1000),
			anime(root2, "Root Season 2", "2017-04-01", core.MediaShow, 700),
			anime(other2, "Other Season 2", "2021-01-10", core.MediaShow, 900),
			anime(other1, "Other", "2019-07-08", core.MediaShow, 600),
			anime(filmID, "A film", "2022-06-01", core.MediaMovie, 100),
			anime(lone, "Unmapped", "2010-01-01", core.MediaShow, 500),
		},
	})
	require.True(t, ok)
	assert.Equal(t, "WIT STUDIO", branch.Label)
	var titles []string
	var picks []core.TreePick
	for _, n := range branch.Nodes {
		titles = append(titles, n.Title)
		picks = append(picks, n.Pick)
	}
	assert.Equal(t, []string{"Other", "A film", "Unmapped"}, titles,
		"the root's second season is gone and the other show appears once, from its first season")
	assert.Equal(t, []core.TreePick{core.PickNext, core.PickNext, core.PickBestKnown}, picks)
}
