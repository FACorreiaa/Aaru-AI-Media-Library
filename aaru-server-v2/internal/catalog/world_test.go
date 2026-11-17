package catalog

import (
	"aaru-go-api/internal/core"
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GRAPH-007: a World, built from fake sources.

// universe is one source that answers for every title with every link it takes part in, as a
// provider that knows a whole franchise does.
func universe(name string, edges ...RelatedEdge) *fakeRelations {
	source := &fakeRelations{name: name, answers: map[string]Relations{}}
	for _, e := range edges {
		for _, n := range []RelatedNode{*e.From, e.To} {
			key := NodeKeys(n)[0]
			r := source.answers[key]
			r.Edges = append(r.Edges, e)
			source.answers[key] = r
		}
	}
	return source
}

func link(from RelatedNode, relation core.Relation, to RelatedNode) RelatedEdge {
	return RelatedEdge{From: &from, To: to, Relation: relation}
}

func show(tmdb, title, date string) RelatedNode {
	return RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: tmdb}, Title: title, ReleaseDate: &date}
}

func anime(anilist, title, date string) RelatedNode {
	return RelatedNode{Type: core.MediaShow, IsAnime: true, IDs: core.ExternalIDs{AniList: anilist}, Title: title, ReleaseDate: &date}
}

func worldTitles(w World, lane WorldLane) []string {
	var titles []string
	for _, t := range w.Titles {
		if t.Lane == lane {
			titles = append(titles, t.Title)
		}
	}
	return titles
}

func worldTitle(t *testing.T, w World, title string) WorldTitle {
	t.Helper()
	for _, wt := range w.Titles {
		if wt.Title == title {
			return wt
		}
	}
	require.Failf(t, "missing title", "%q not in the World", title)
	return WorldTitle{}
}

// duneSources is two novels, the two films of the first, a spin-off show and another version of
// the first film.
func duneSources() []RelationSource {
	dune, messiah := book("OL1W", "Dune", 1965), book("OL2W", "Dune Messiah", 1969)
	one, two := film("438631", "Dune: Part One", "2021-09-15"), film("693134", "Dune: Part Two", "2024-02-27")
	prophecy := show("90228", "Dune: Prophecy", "2024-11-17")
	lynch := film("841", "Dune (1984)", "1984-12-14")
	return []RelationSource{universe("all",
		link(dune, core.RelationSequel, messiah),
		link(one, core.RelationSequel, two),
		link(one, core.RelationSource, dune),
		link(one, core.RelationSpinOff, prophecy),
		link(one, core.RelationAlternative, lynch),
	)}
}

func TestWorldLaysOneLanePerKindFromTheFirstTitle(t *testing.T) {
	world, found := BuildWorld(context.Background(), film("693134", "Dune: Part Two", "2024-02-27"), duneSources(), nil)
	require.True(t, found)
	assert.Equal(t, "openlibrary:OL1W", world.RootKey, "the first-released title is the root, whichever was asked about")
	assert.Equal(t, "Dune", world.Name)
	assert.False(t, world.Truncated)
	assert.False(t, world.Partial)

	assert.Equal(t, []string{"Dune", "Dune Messiah"}, worldTitles(world, LaneBook))
	assert.Equal(t, []string{"Dune: Part One", "Dune: Part Two"}, worldTitles(world, LaneFilm))
	assert.Equal(t, []string{"Dune: Prophecy"}, worldTitles(world, LaneShow))
	var lanes []WorldLane
	for _, wt := range world.Titles {
		if len(lanes) == 0 || lanes[len(lanes)-1] != wt.Lane {
			lanes = append(lanes, wt.Lane)
		}
	}
	assert.Equal(t, []WorldLane{LaneBook, LaneFilm, LaneShow}, lanes, "lanes by the release of their first title")

	assert.True(t, worldTitle(t, world, "Dune: Prophecy").Side, "a spin-off that leads nowhere further is a side title")
	assert.False(t, worldTitle(t, world, "Dune: Part Two").Side)
	assert.Equal(t, 1, worldTitle(t, world, "Dune: Part Two").LanePosition)
	for _, wt := range world.Titles {
		assert.NotEqual(t, "Dune (1984)", wt.Title, "another version is not the same story going on")
	}
	assert.Contains(t, world.Links, GraphEdge{From: "openlibrary:OL1W", To: "tmdb:movie:438631", Relation: core.RelationAdaptation},
		"a source is written forward, as an adaptation")
	assert.True(t, world.Has([]string{"imdb:tt0", "tmdb:show:90228"}))
	assert.False(t, world.Has([]string{"tmdb:movie:841"}))
}

func TestWorldIsTheSameFromAnyOfItsTitles(t *testing.T) {
	anchors := []RelatedNode{
		book("OL2W", "Dune Messiah", 1969),
		film("438631", "Dune: Part One", "2021-09-15"),
		show("90228", "Dune: Prophecy", "2024-11-17"),
	}
	want, found := BuildWorld(context.Background(), book("OL1W", "Dune", 1965), duneSources(), nil)
	require.True(t, found)
	for _, anchor := range anchors {
		got, found := BuildWorld(context.Background(), anchor, duneSources(), nil)
		require.True(t, found, anchor.Title)
		assert.Equal(t, want.RootKey, got.RootKey, anchor.Title)
		assert.Equal(t, want.AllKeys(), got.AllKeys(), anchor.Title)
		assert.ElementsMatch(t, want.Links, got.Links, anchor.Title)
	}
}

func TestWorldPutsASideStoryAfterTheTitleItHangsFrom(t *testing.T) {
	first, second := anime("1", "Season one", "2010-04-01"), anime("2", "Season two", "2012-04-01")
	ova := anime("3", "The OVA", "2011-01-01")
	special := anime("4", "A later special", "2011-06-01")
	movie := RelatedNode{Type: core.MediaMovie, IsAnime: true, IDs: core.ExternalIDs{AniList: "5"}, Title: "The film", Year: ptr(2013)}
	sources := []RelationSource{universe("anilist",
		link(first, core.RelationSequel, second),
		link(special, core.RelationParent, first),
		link(first, core.RelationSideStory, ova),
		link(second, core.RelationSequel, movie),
	)}
	world, found := BuildWorld(context.Background(), second, sources, nil)
	require.True(t, found)
	assert.Equal(t, []string{"Season one", "The OVA", "A later special", "Season two", "The film"}, worldTitles(world, LaneAnime),
		"side stories sit after their parent in release order; an anime film continues the series in its lane")
	assert.True(t, worldTitle(t, world, "The OVA").Side)
	assert.True(t, worldTitle(t, world, "A later special").Side, "a parent written backwards is a side story")
	assert.False(t, worldTitle(t, world, "The film").Side)
}

func TestWorldCutsAUniversePastItsBoundsAndSaysSo(t *testing.T) {
	var edges []RelatedEdge
	for i := range WorldMaxTitles + 10 {
		from := film(fmt.Sprint(1000+i), fmt.Sprintf("Film %d", i), fmt.Sprintf("%04d-01-01", 1950+i))
		to := film(fmt.Sprint(1001+i), fmt.Sprintf("Film %d", i+1), fmt.Sprintf("%04d-01-01", 1951+i))
		edges = append(edges, link(from, core.RelationSequel, to))
	}
	world, found := BuildWorld(context.Background(), film("1000", "Film 0", "1950-01-01"), []RelationSource{universe("collection", edges...)}, nil)
	require.True(t, found)
	assert.Len(t, world.Titles, WorldMaxTitles)
	assert.True(t, world.Truncated)
	assert.Equal(t, "Film 0", world.Titles[0].Title, "cut nearest the first title")
}

func TestWorldStopsAtItsReach(t *testing.T) {
	// Each step changes medium, so each costs a hop: only WorldReach of them are walked.
	var edges []RelatedEdge
	previous := book("OL0W", "Step 0", 1900)
	for i := 1; i <= WorldReach+3; i++ {
		var next RelatedNode
		if i%2 == 1 {
			next = film(fmt.Sprint(i), fmt.Sprintf("Step %d", i), fmt.Sprintf("%04d-01-01", 1900+i))
		} else {
			next = book(fmt.Sprintf("OL%dW", i), fmt.Sprintf("Step %d", i), 1900+i)
		}
		edges = append(edges, link(previous, core.RelationAdaptation, next))
		previous = next
	}
	world, found := BuildWorld(context.Background(), book("OL0W", "Step 0", 1900), []RelationSource{universe("wiki", edges...)}, nil)
	require.True(t, found)
	assert.Len(t, world.Titles, WorldReach+1)
	assert.False(t, world.Truncated, "the reach is the World's edge, not a cut")
}

func TestATitleRelatedToNothingHasNoWorld(t *testing.T) {
	_, found := BuildWorld(context.Background(), film("7", "Alone", "2020-01-01"), []RelationSource{universe("all")}, nil)
	assert.False(t, found)
	_, found = BuildWorld(context.Background(), RelatedNode{Type: core.MediaMovie, Title: "No id"}, duneSources(), nil)
	assert.False(t, found, "a title with no id is never matched by name")

	lynch := film("841", "Dune (1984)", "1984-12-14")
	_, found = BuildWorld(context.Background(), lynch, duneSources(), nil)
	assert.False(t, found, "a title joined only by a relation a World does not walk has none")
}

func TestWorldWithAFailingSourceIsPartialNeverAnError(t *testing.T) {
	failing := &fakeRelations{name: "down", err: errors.New("provider is down")}
	world, found := BuildWorld(context.Background(), film("438631", "Dune: Part One", "2021-09-15"),
		append(duneSources(), failing), nil)
	require.True(t, found)
	assert.True(t, world.Partial)
	assert.Equal(t, "Dune", world.Name)

	world, found = BuildWorld(context.Background(), film("438631", "Dune: Part One", "2021-09-15"), []RelationSource{failing}, nil)
	assert.False(t, found)
	assert.True(t, world.Partial, "nothing found because a source failed is not the same as nothing related")
}

func TestWorldKeepsTheStartAnEarlierBuildHad(t *testing.T) {
	// Seen from Part Two alone the films are the whole World; a World already built around these
	// ids starts at the novel, and the walk goes back to it.
	one, two := film("438631", "Dune: Part One", "2021-09-15"), film("693134", "Dune: Part Two", "2024-02-27")
	dune := book("OL1W", "Dune", 1965)
	filmsOnly := universe("collection", link(one, core.RelationSequel, two))
	novel := &fakeRelations{name: "wiki", answers: map[string]Relations{
		"openlibrary:OL1W": {Edges: []RelatedEdge{{To: one, Relation: core.RelationAdaptation}}},
	}}
	sources := []RelationSource{filmsOnly, novel}

	alone, found := BuildWorld(context.Background(), two, sources, nil)
	require.True(t, found)
	assert.Equal(t, "tmdb:movie:438631", alone.RootKey)

	var asked []string
	known := func(_ context.Context, keys []string) []RelatedNode {
		asked = keys
		return []RelatedNode{dune}
	}
	world, found := BuildWorld(context.Background(), two, sources, known)
	require.True(t, found)
	assert.Equal(t, "openlibrary:OL1W", world.RootKey)
	assert.Equal(t, "Dune", world.Name)
	assert.Len(t, world.Titles, 3)
	assert.Contains(t, asked, "tmdb:movie:693134")
}

func TestLaneOf(t *testing.T) {
	assert.Equal(t, LaneFilm, LaneOf(RelatedNode{Type: core.MediaMovie}))
	assert.Equal(t, LaneAnime, LaneOf(RelatedNode{Type: core.MediaMovie, IsAnime: true}))
	assert.Equal(t, LaneShow, LaneOf(RelatedNode{Type: core.MediaShow}))
	assert.Equal(t, LaneAnime, LaneOf(RelatedNode{Type: core.MediaShow, IsAnime: true}))
	assert.Equal(t, LaneBook, LaneOf(RelatedNode{Type: core.MediaBook}))
	assert.Equal(t, LaneManga, LaneOf(RelatedNode{Type: core.MediaManga}))
	assert.Equal(t, LaneAlbum, LaneOf(RelatedNode{Type: core.MediaAlbum}))
}
