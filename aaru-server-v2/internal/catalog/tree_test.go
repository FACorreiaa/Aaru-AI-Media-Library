package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/testdb"
	"context"
	"errors"
	"log/slog"
	"sync"
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
	}, nil)
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

// castSource is a credit source with a director and two actors; fail names the people whose
// works cannot be read.
type castSource struct {
	fail  map[string]bool
	reads map[string]int
	mu    sync.Mutex
}

func (c *castSource) CreditSourceName() string       { return "cast-test" }
func (c *castSource) CreditKey(n RelatedNode) string { return "movie:" + n.IDs.TMDB }

func (c *castSource) People(context.Context, RelatedNode) ([]Credit, error) {
	c.count("people")
	return []Credit{
		{Kind: core.BranchDirector, ID: "1", Name: "A Director"},
		{Kind: core.BranchDirector, ID: "9", Name: "A Co-director"},
		{Kind: core.BranchLeadActor, ID: "2", Name: "A Lead", Media: core.MediaMovie},
		{Kind: core.BranchSecondActor, ID: "3", Name: "A Second", Media: core.MediaMovie},
	}, nil
}

func (c *castSource) Works(_ context.Context, credit Credit) ([]CreditedWork, error) {
	c.count(credit.ID)
	if c.fail[credit.ID] {
		return nil, errors.New("provider down")
	}
	date := "2020-01-01"
	return []CreditedWork{{Score: 1, RelatedNode: RelatedNode{
		Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: "9" + credit.ID}, Title: "By " + credit.Name, ReleaseDate: &date,
	}}}, nil
}

func (c *castSource) count(key string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.reads[key]++
}

// GRAPH-006: the cast is read only when asked for, and one person failing leaves the others.
func TestTreePeopleAddTheCastWhenAskedAndSurviveOneFailing(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	source := &castSource{fail: map[string]bool{"3": true}, reads: map[string]int{}}
	service := NewTreeService(NewRelationService(store, nil, nil), []CreditSource{source}, nil)
	centre := film(randomID(), "Root", "2019-01-01")
	names := func(people []credited) []string {
		out := make([]string, len(people))
		for i, p := range people {
			out[i] = p.credit.Name
		}
		return out
	}

	people, err := service.people(ctx, centre, false)
	require.NoError(t, err)
	assert.Equal(t, []string{"A Director"}, names(people), "without the cast: the first person who made it, nobody else")
	assert.Equal(t, map[string]int{"people": 1, "1": 1}, source.reads, "no actor's works are read unasked")

	people, err = service.people(ctx, centre, true)
	require.Error(t, err, "the second actor's works failed: the answer is short")
	assert.Equal(t, []string{"A Director", "A Lead"}, names(people), "the others are still there, in order")
	assert.Equal(t, map[string]int{"people": 1, "1": 1, "2": 1, "3": 1}, source.reads, "the title and the director come from the cache")

	source.fail = nil
	people, err = service.people(ctx, centre, true)
	require.NoError(t, err)
	assert.Equal(t, []string{"A Director", "A Lead", "A Second"}, names(people))
	assert.Equal(t, 2, source.reads["3"], "only what failed is read again")
	assert.Equal(t, 1, source.reads["2"])
}
