package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GRAPH-001: the relation graph, built from fake sources, and each source against canned JSON.

// fakeRelations answers by the node's first key; a node it has no answer for gets no edges.
type fakeRelations struct {
	name    string
	answers map[string]Relations
	err     error
	mu      sync.Mutex
	asked   []string
}

func (f *fakeRelations) RelationSourceName() string { return f.name }

func (f *fakeRelations) RelationKey(n RelatedNode) string {
	keys := NodeKeys(n)
	if len(keys) == 0 {
		return ""
	}
	return keys[0]
}

func (f *fakeRelations) Relations(_ context.Context, n RelatedNode) (Relations, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	key := f.RelationKey(n)
	f.asked = append(f.asked, key)
	if f.err != nil {
		return Relations{}, f.err
	}
	for _, k := range NodeKeys(n) {
		if r, ok := f.answers[k]; ok {
			return r, nil
		}
	}
	return Relations{Edges: []RelatedEdge{}}, nil
}

func film(tmdb, title, date string) RelatedNode {
	return RelatedNode{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: tmdb}, Title: title, ReleaseDate: &date}
}

func book(ol, title string, year int) RelatedNode {
	return RelatedNode{Type: core.MediaBook, IDs: core.ExternalIDs{OpenLibrary: ol}, Title: title, Year: &year}
}

func nodeByTitle(t *testing.T, g RelationGraph, title string) GraphNode {
	t.Helper()
	for _, n := range g.Nodes {
		if n.Title == title {
			return n
		}
	}
	require.Failf(t, "missing node", "%q not in graph", title)
	return GraphNode{}
}

func lotrSources() []RelationSource {
	fellowship, towers, king := film("120", "The Fellowship of the Ring", "2001-12-19"),
		film("121", "The Two Towers", "2002-12-18"), film("122", "The Return of the King", "2003-12-17")
	fBook, tBook, kBook := book("OL1W", "The Fellowship of the Ring (novel)", 1954),
		book("OL2W", "The Two Towers (novel)", 1954), book("OL3W", "The Return of the King (novel)", 1955)
	collection := &fakeRelations{name: "collection", answers: map[string]Relations{}}
	chain := Relations{Edges: []RelatedEdge{
		{From: &fellowship, To: towers, Relation: core.RelationSequel},
		{From: &towers, To: king, Relation: core.RelationSequel},
	}}
	for _, k := range []string{"tmdb:movie:120", "tmdb:movie:121", "tmdb:movie:122"} {
		collection.answers[k] = chain
	}
	wiki := &fakeRelations{name: "wiki", answers: map[string]Relations{
		"tmdb:movie:120":   {Edges: []RelatedEdge{{To: fBook, Relation: core.RelationSource}}},
		"tmdb:movie:121":   {Edges: []RelatedEdge{{To: tBook, Relation: core.RelationSource}}},
		"openlibrary:OL1W": {Edges: []RelatedEdge{{To: tBook, Relation: core.RelationSequel}}},
		"openlibrary:OL2W": {Edges: []RelatedEdge{{To: kBook, Relation: core.RelationSequel}}},
	}}
	return []RelationSource{collection, wiki}
}

func TestRelationGraphLaysTheChainOutAndHangsBooksUnderTheirFilms(t *testing.T) {
	centre := film("121", "The Two Towers", "2002-12-18")
	g := BuildRelationGraph(context.Background(), centre, lotrSources(), OrderRelease)

	assert.False(t, g.Partial)
	for i, title := range []string{"The Fellowship of the Ring", "The Two Towers", "The Return of the King"} {
		n := nodeByTitle(t, g, title)
		assert.Equal(t, i, n.Rank, title)
		assert.Equal(t, 0, n.Lane, title)
		assert.True(t, n.MainChain, title)
	}
	assert.True(t, nodeByTitle(t, g, "The Two Towers").Centre)

	fBook := nodeByTitle(t, g, "The Fellowship of the Ring (novel)")
	assert.Equal(t, 0, fBook.Rank)
	assert.Equal(t, 1, fBook.Lane)
	assert.False(t, fBook.MainChain)
	tBook := nodeByTitle(t, g, "The Two Towers (novel)")
	assert.Equal(t, 1, tBook.Rank, "under the film it was adapted into")
	assert.Equal(t, 1, tBook.Lane)
	// The third book continues the second, a step after it, on the same lane.
	kBook := nodeByTitle(t, g, "The Return of the King (novel)")
	assert.Equal(t, 2, kBook.Rank)
	assert.Equal(t, 1, kBook.Lane)

	// Edges are written forward: the book's adaptation is the film, not the film's source the book.
	assert.Contains(t, g.Edges, GraphEdge{From: tBook.Key, To: nodeByTitle(t, g, "The Two Towers").Key, Relation: core.RelationAdaptation})
	assert.Contains(t, g.Edges, GraphEdge{From: fBook.Key, To: tBook.Key, Relation: core.RelationSequel})
}

func TestRelationGraphMergesByIDNeverByName(t *testing.T) {
	centre := film("1", "Dune", "2021-09-15")
	sameName := film("2", "Dune", "1984-12-14")
	sameFilm := RelatedNode{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: "1", IMDB: "tt1160419"}, Wikidata: "Q1"}
	source := &fakeRelations{name: "s", answers: map[string]Relations{
		"tmdb:movie:1": {Self: &sameFilm, Edges: []RelatedEdge{{To: sameName, Relation: core.RelationAlternative}}},
	}}
	g := BuildRelationGraph(context.Background(), centre, []RelationSource{source}, OrderRelease)

	require.Len(t, g.Nodes, 2, "the 1984 film shares a name, not an id")
	centreNode := g.Nodes[0]
	if !centreNode.Centre {
		centreNode = g.Nodes[1]
	}
	assert.Equal(t, "tt1160419", centreNode.IDs.IMDB, "what a source learned about the title fills it")
	assert.Equal(t, "Q1", centreNode.Wikidata)
}

func TestRelationGraphStoryOrderFollowsTheSeriesNumbers(t *testing.T) {
	saga := "Q22092344"
	ep := func(tmdb, title, date string, n float64) RelatedNode {
		f := film(tmdb, title, date)
		f.Series = []SeriesPlace{{Series: saga, Ordinal: n}}
		return f
	}
	iv, v, i := ep("11", "A New Hope", "1977-05-25", 4), ep("1891", "The Empire Strikes Back", "1980-05-20", 5),
		ep("1893", "The Phantom Menace", "1999-05-19", 1)
	chain := Relations{Edges: []RelatedEdge{
		{From: &iv, To: v, Relation: core.RelationSequel},
		{From: &v, To: i, Relation: core.RelationSequel},
	}}
	source := &fakeRelations{name: "s", answers: map[string]Relations{
		"tmdb:movie:11": chain, "tmdb:movie:1891": chain, "tmdb:movie:1893": chain,
	}}

	release := BuildRelationGraph(context.Background(), iv, []RelationSource{source}, OrderRelease)
	assert.True(t, release.StoryOrderAvailable)
	assert.Equal(t, OrderRelease, release.Order)
	assert.Equal(t, 0, nodeByTitle(t, release, "A New Hope").Rank)
	assert.Equal(t, 2, nodeByTitle(t, release, "The Phantom Menace").Rank)

	story := BuildRelationGraph(context.Background(), iv, []RelationSource{source}, OrderStory)
	assert.Equal(t, OrderStory, story.Order)
	assert.Equal(t, 0, nodeByTitle(t, story, "The Phantom Menace").Rank)
	assert.Equal(t, 1, nodeByTitle(t, story, "A New Hope").Rank)
	assert.Equal(t, 2, nodeByTitle(t, story, "The Empire Strikes Back").Rank)
}

func TestRelationGraphWithoutStoryOrderStaysInReleaseOrder(t *testing.T) {
	g := BuildRelationGraph(context.Background(), film("121", "The Two Towers", "2002-12-18"), lotrSources(), OrderStory)
	assert.False(t, g.StoryOrderAvailable)
	assert.Equal(t, OrderRelease, g.Order)
}

func TestRelationGraphFailingSourceIsPartialNeverAnError(t *testing.T) {
	broken := &fakeRelations{name: "broken", err: errors.New("down")}
	centre := film("121", "The Two Towers", "2002-12-18")
	g := BuildRelationGraph(context.Background(), centre, append(lotrSources()[:1], broken), OrderRelease)
	assert.True(t, g.Partial)
	assert.Len(t, g.Nodes, 3, "the collection still answered")
}

func TestRelationGraphStopsAtTheCapAndTheReach(t *testing.T) {
	var many []RelatedEdge
	for i := range 60 {
		many = append(many, RelatedEdge{To: book(fmt.Sprintf("OL%dW", i+10), fmt.Sprintf("Book %d", i), 2000), Relation: core.RelationAdaptation})
	}
	source := &fakeRelations{name: "s", answers: map[string]Relations{"tmdb:movie:1": {Edges: many}}}
	g := BuildRelationGraph(context.Background(), film("1", "Film", "2000-01-01"), []RelationSource{source}, OrderRelease)
	assert.Len(t, g.Nodes, RelationMaxNodes)

	// Two hops out: the film's book is asked about, the book's own adaptation is shown, not asked.
	hop1, hop2 := book("OL1W", "Hop one", 1990), book("OL2W", "Hop two", 1995)
	hop3 := book("OL3W", "Hop three", 1999)
	walker := &fakeRelations{name: "w", answers: map[string]Relations{
		"tmdb:movie:1":     {Edges: []RelatedEdge{{To: hop1, Relation: core.RelationSource}}},
		"openlibrary:OL1W": {Edges: []RelatedEdge{{To: hop2, Relation: core.RelationAdaptation}}},
		"openlibrary:OL2W": {Edges: []RelatedEdge{{To: hop3, Relation: core.RelationAdaptation}}},
	}}
	g = BuildRelationGraph(context.Background(), film("1", "Film", "2000-01-01"), []RelationSource{walker}, OrderRelease)
	assert.Len(t, g.Nodes, 3)
	assert.NotContains(t, walker.asked, "openlibrary:OL2W")
}

func TestStartHereSkipsFinishedAndDroppedChainTitles(t *testing.T) {
	g := BuildRelationGraph(context.Background(), film("121", "The Two Towers", "2002-12-18"), lotrSources(), OrderRelease)
	key := func(title string) string { return nodeByTitle(t, g, title).Key }

	assert.Equal(t, key("The Fellowship of the Ring"), *g.StartHere(nil))
	status := map[string]core.LibraryStatus{
		key("The Fellowship of the Ring"): core.StatusFinished,
		key("The Two Towers"):             core.StatusDropped,
		// A finished book is not on the chain: it never moves the start.
		key("The Two Towers (novel)"): core.StatusFinished,
	}
	assert.Equal(t, key("The Return of the King"), *g.StartHere(status))
	status[key("The Return of the King")] = core.StatusFinished
	assert.Nil(t, g.StartHere(status))
}

func TestRelationCanonicalWritesEachPairForward(t *testing.T) {
	for in, want := range map[core.Relation]core.Relation{
		core.RelationPrequel: core.RelationSequel, core.RelationSource: core.RelationAdaptation,
		core.RelationParent: core.RelationSideStory,
	} {
		got, flipped := in.Canonical()
		assert.Equal(t, want, got)
		assert.True(t, flipped)
	}
	got, flipped := core.RelationSpinOff.Canonical()
	assert.Equal(t, core.RelationSpinOff, got)
	assert.False(t, flipped)
}

// MARK: - Sources against canned JSON

func TestAniListRelationsMapsTypesAndLeavesNoiseOut(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		assert.Contains(t, string(req.Body), "relationType(version: 2)")
		return provider.Response{Status: 200, Body: []byte(`{"data":{"Media":{
"id":16498,"idMal":16498,"type":"ANIME","format":"TV","title":{"english":"Attack on Titan"},
"startDate":{"year":2013,"month":4,"day":7},"coverImage":{"large":"https://img/aot.jpg"},
"relations":{"edges":[
 {"relationType":"SEQUEL","node":{"id":20958,"idMal":25777,"type":"ANIME","format":"TV","title":{"english":"Attack on Titan Season 2"},"startDate":{"year":2017,"month":4,"day":1}}},
 {"relationType":"SOURCE","node":{"id":53390,"idMal":23390,"type":"MANGA","format":"MANGA","title":{"romaji":"Shingeki no Kyojin"},"startDate":{"year":2009}}},
 {"relationType":"CHARACTER","node":{"id":1,"type":"ANIME","format":"OVA","title":{"romaji":"Chibi"}}},
 {"relationType":"OTHER","node":{"id":2,"type":"ANIME","format":"MUSIC","title":{"romaji":"MV"}}},
 {"relationType":"SIDE_STORY","node":{"id":18397,"type":"ANIME","format":"OVA","title":{"romaji":"Shingeki no Kyojin OVA"}}}
]}}}}`)}
	})
	a := &AniList{Client: testClient(stub, "anilist")}
	r, err := a.Relations(context.Background(), RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{AniList: "16498"}})
	require.NoError(t, err)
	require.NotNil(t, r.Self)
	assert.Equal(t, "tv", r.Self.Format)
	require.Len(t, r.Edges, 3)
	assert.Equal(t, core.RelationSequel, r.Edges[0].Relation)
	assert.Equal(t, "20958", r.Edges[0].To.IDs.AniList)
	assert.Equal(t, "2017-04-01", *r.Edges[0].To.ReleaseDate)
	assert.Equal(t, core.RelationSource, r.Edges[1].Relation)
	assert.Equal(t, core.MediaManga, r.Edges[1].To.Type)
	assert.Equal(t, core.RelationSideStory, r.Edges[2].Relation)
	assert.Equal(t, "ova", r.Edges[2].To.Format)
	assert.Empty(t, a.RelationKey(RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: "1429"}}))
}

func TestTMDBRelationsChainTheCollectionByRelease(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		switch strings.TrimPrefix(urlPath(req.URL), "/3") {
		case "/movie/11":
			return provider.Response{Status: 200, Body: []byte(`{"id":11,"belongs_to_collection":{"id":10}}`)}
		case "/collection/10":
			return provider.Response{Status: 200, Body: []byte(`{"parts":[
{"id":1893,"title":"The Phantom Menace","release_date":"1999-05-19","poster_path":"/i.jpg"},
{"id":11,"title":"A New Hope","release_date":"1977-05-25"},
{"id":1891,"title":"The Empire Strikes Back","release_date":"1980-05-20"},
{"id":9999,"title":"Untitled","release_date":""}]}`)}
		case "/movie/603":
			return provider.Response{Status: 200, Body: []byte(`{"id":603,"belongs_to_collection":null}`)}
		}
		return provider.Response{Status: 404, Body: []byte(`{}`)}
	})
	tmdb := &TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}
	r, err := tmdb.Relations(context.Background(), film("11", "A New Hope", "1977-05-25"))
	require.NoError(t, err)
	require.Len(t, r.Edges, 3)
	titles := []string{r.Edges[0].From.Title, r.Edges[0].To.Title, r.Edges[1].To.Title, r.Edges[2].To.Title}
	assert.Equal(t, []string{"A New Hope", "The Empire Strikes Back", "The Phantom Menace", "Untitled"}, titles)
	assert.Equal(t, "https://image.tmdb.org/t/p/w500/i.jpg", *r.Edges[1].To.PosterURL)

	r, err = tmdb.Relations(context.Background(), film("603", "The Matrix", "1999-03-31"))
	require.NoError(t, err)
	assert.Empty(t, r.Edges)
	assert.Empty(t, tmdb.RelationKey(RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: "1"}}))
}

func TestWikidataRelationsReadKindsDatesAndSeries(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		q := urlQuery(req.URL)
		switch q.Get("action") {
		case "query":
			assert.Equal(t, "haswbstatement:P4947=120|P345=tt0120737", q.Get("srsearch"))
			return provider.Response{Status: 200, Body: []byte(`{"query":{"search":[{"title":"Q127367"}]}}`)}
		case "wbgetentities":
			if q.Get("ids") == "Q127367" {
				return provider.Response{Status: 200, Body: []byte(`{"entities":{"Q127367":{"labels":{"mul":{"value":"Fellowship"}},"claims":{
"P179":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q190214"}}},"qualifiers":{"P1545":[{"datavalue":{"value":"1"}}],"P156":[{"datavalue":{"value":{"id":"Q164963"}}}]}}],
"P144":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q208002"}}}}],
"P4969":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q2353071"}}}},{"rank":"deprecated","mainsnak":{"datavalue":{"value":{"id":"Q5"}}}}]
}}}}`)}
			}
			assert.Equal(t, "Q164963|Q208002|Q2353071", q.Get("ids"))
			return provider.Response{Status: 200, Body: []byte(`{"entities":{
"Q164963":{"labels":{"mul":{"value":"The Two Towers"}},"claims":{"P4947":[{"rank":"normal","mainsnak":{"datavalue":{"value":"121"}}}],
  "P577":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"time":"+2003-01-02T00:00:00Z","precision":11}}}},{"rank":"normal","mainsnak":{"datavalue":{"value":{"time":"+2002-12-18T00:00:00Z","precision":11}}}}],
  "P179":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q190214"}}},"qualifiers":{"P1545":[{"datavalue":{"value":"2"}}]}}]}},
"Q208002":{"labels":{"en":{"value":"The Fellowship of the Ring"},"mul":{"value":"x"}},"claims":{"P648":[{"rank":"normal","mainsnak":{"datavalue":{"value":"OL123M"}}},{"rank":"normal","mainsnak":{"datavalue":{"value":"OL15331214W"}}}],
  "P577":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"time":"+1954-00-00T00:00:00Z","precision":9}}}}]}},
"Q2353071":{"labels":{"en":{"value":"The Lord of the Rings: The Fellowship of the Ring (video game)"}},"claims":{}}
}}`)}
		}
		return provider.Response{Status: 404, Body: []byte(`{}`)}
	})
	w := &Wikidata{Client: testClient(stub, "wikidata")}
	centre := RelatedNode{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: "120", IMDB: "tt0120737"}}
	assert.Equal(t, "wikidata:P4947=120", w.RelationKey(centre))

	r, err := w.Relations(context.Background(), centre)
	require.NoError(t, err)
	require.NotNil(t, r.Self)
	assert.Equal(t, "Q127367", r.Self.Wikidata)
	assert.Equal(t, []SeriesPlace{{Series: "Q190214", Ordinal: 1}}, r.Self.Series)
	require.Len(t, r.Edges, 2, "the game carries no id Aaru tracks")

	sequel := r.Edges[0]
	assert.Equal(t, core.RelationSequel, sequel.Relation)
	assert.Equal(t, core.MediaMovie, sequel.To.Type)
	assert.Equal(t, "121", sequel.To.IDs.TMDB)
	assert.Equal(t, "The Two Towers", sequel.To.Title)
	assert.Equal(t, "2002-12-18", *sequel.To.ReleaseDate, "the earliest release")
	assert.Equal(t, []SeriesPlace{{Series: "Q190214", Ordinal: 2}}, sequel.To.Series)

	source := r.Edges[1]
	assert.Equal(t, core.RelationSource, source.Relation)
	assert.Equal(t, core.MediaBook, source.To.Type)
	assert.Equal(t, "OL15331214W", source.To.IDs.OpenLibrary, "a work, never an edition")
	assert.Equal(t, "The Fellowship of the Ring", source.To.Title)
	assert.Equal(t, 1954, *source.To.Year)
	assert.Nil(t, source.To.ReleaseDate)
}

func TestWikidataWithNoItemHasNoRelations(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		assert.True(t, strings.Contains(req.URL, "list=search"))
		return provider.Response{Status: 200, Body: []byte(`{"query":{"search":[]}}`)}
	})
	w := &Wikidata{Client: testClient(stub, "wikidata")}
	r, err := w.Relations(context.Background(), RelatedNode{Type: core.MediaBook, IDs: core.ExternalIDs{OpenLibrary: "OL1W"}})
	require.NoError(t, err)
	assert.Nil(t, r.Self)
	assert.Empty(t, r.Edges)
	assert.Empty(t, w.RelationKey(RelatedNode{Type: core.MediaBook, IDs: core.ExternalIDs{OpenLibrary: "bad value!"}}))
}

func TestRelationGraphOrdersTheChainBySequelLinksBeforeDates(t *testing.T) {
	season := func(id, title string) RelatedNode {
		return RelatedNode{Type: core.MediaShow, IsAnime: true, IDs: core.ExternalIDs{AniList: id}, Title: title}
	}
	s1, s2, s3 := season("1", "Season 1"), season("2", "Season 2"), season("3", "Season 3")
	// Undated, and the source lists them out of order: only the links say which comes first.
	source := &fakeRelations{name: "s", answers: map[string]Relations{
		"anilist:2": {Edges: []RelatedEdge{
			{To: s3, Relation: core.RelationSequel}, {To: s1, Relation: core.RelationPrequel},
		}},
	}}
	g := BuildRelationGraph(context.Background(), s2, []RelationSource{source}, OrderRelease)
	assert.Equal(t, 0, nodeByTitle(t, g, "Season 1").Rank)
	assert.Equal(t, 1, nodeByTitle(t, g, "Season 2").Rank)
	assert.Equal(t, 2, nodeByTitle(t, g, "Season 3").Rank)
}

type chainOnlyFake struct{ *fakeRelations }

func (chainOnlyFake) ChainOnly() bool { return true }

func TestChainOnlySourceIsNotAskedAboutSideTitles(t *testing.T) {
	ova := RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{AniList: "9"}, Title: "OVA"}
	sequel := RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{AniList: "2"}, Title: "Season 2"}
	source := chainOnlyFake{&fakeRelations{name: "anilist", answers: map[string]Relations{
		"anilist:1": {Edges: []RelatedEdge{{To: ova, Relation: core.RelationSideStory}, {To: sequel, Relation: core.RelationSequel}}},
	}}}
	centre := RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{AniList: "1"}, Title: "Season 1"}
	g := BuildRelationGraph(context.Background(), centre, []RelationSource{source}, OrderRelease)
	assert.Len(t, g.Nodes, 3)
	assert.ElementsMatch(t, []string{"anilist:1", "anilist:2"}, source.asked, "the OVA is shown, never asked about")
}

// A show based on a book series (Game of Thrones, on "A Song of Ice and Fire") is related to the
// novels: the series item carries no id Aaru tracks, its parts do.
func TestWikidataSeriesSourceStandsForItsBooks(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		q := urlQuery(req.URL)
		switch {
		case q.Get("action") == "query":
			return provider.Response{Status: 200, Body: []byte(`{"query":{"search":[{"title":"Q23572"}]}}`)}
		case q.Get("ids") == "Q23572":
			return provider.Response{Status: 200, Body: []byte(`{"entities":{"Q23572":{"labels":{"en":{"value":"Game of Thrones"}},"claims":{
"P4983":[{"rank":"normal","mainsnak":{"datavalue":{"value":"1399"}}}],
"P345":[{"rank":"normal","mainsnak":{"datavalue":{"value":"tt0944947"}}}],
"P144":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q45875"}}}}]}}}}`)}
		case q.Get("ids") == "Q45875":
			return provider.Response{Status: 200, Body: []byte(`{"entities":{"Q45875":{"labels":{"en":{"value":"A Song of Ice and Fire"}},"claims":{
"P527":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q1751870"}}}},{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q10371726"}}}}]}}}}`)}
		case q.Get("ids") == "Q1751870|Q10371726":
			return provider.Response{Status: 200, Body: []byte(`{"entities":{
"Q1751870":{"labels":{"en":{"value":"A Game of Thrones"}},"claims":{
  "P648":[{"rank":"normal","mainsnak":{"datavalue":{"value":"OL1955941W"}}}],
  "P436":[{"rank":"normal","mainsnak":{"datavalue":{"value":"5a2f4c3e-audiobook"}}}]}},
"Q10371726":{"labels":{"en":{"value":"A Dream of Spring"}},"claims":{}}}}`)}
		}
		return provider.Response{Status: 404, Body: []byte(`{}`)}
	})
	w := &Wikidata{Client: testClient(stub, "wikidata")}
	r, err := w.Relations(context.Background(), RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: "1399"}})
	require.NoError(t, err)
	require.NotNil(t, r.Self)
	assert.Equal(t, "tt0944947", r.Self.IDs.IMDB, "what Wikidata knows about the title itself comes back")
	require.Len(t, r.Edges, 1, "the unwritten book carries no id Aaru tracks")
	assert.Equal(t, core.RelationSource, r.Edges[0].Relation)
	assert.Equal(t, core.MediaBook, r.Edges[0].To.Type, "a novel with an audiobook is still a book")
	assert.Equal(t, "OL1955941W", r.Edges[0].To.IDs.OpenLibrary)
	assert.Empty(t, r.Edges[0].To.IDs.MusicBrainz)
}

// The Action API fails with HTTP 200 and an error object: a failure, never "nothing related".
func TestWikidataErrorBodyIsAFailure(t *testing.T) {
	stub := stubFunc(func(provider.Request) provider.Response {
		return provider.Response{Status: 200, Body: []byte(`{"error":{"code":"ratelimited","info":"slow down"}}`)}
	})
	w := &Wikidata{Client: testClient(stub, "wikidata")}
	_, err := w.Relations(context.Background(), RelatedNode{Type: core.MediaMovie, IDs: core.ExternalIDs{TMDB: "11"}})
	require.Error(t, err)
}

// idSource answers only for nodes carrying the id it reads, as AniList does.
type idSource struct {
	name   string
	key    func(RelatedNode) string
	answer func(RelatedNode) Relations
}

func (s idSource) RelationSourceName() string       { return s.name }
func (s idSource) RelationKey(n RelatedNode) string { return s.key(n) }
func (s idSource) Relations(_ context.Context, n RelatedNode) (Relations, error) {
	return s.answer(n), nil
}

// An anime kept as a TMDB show: Wikidata names its AniList id, and AniList is then asked about the
// same node, so the show is one title in the graph and AniList's chain hangs from it.
func TestRelationGraphAsksASourceAgainOnceAnotherNamesItsID(t *testing.T) {
	byTMDB := idSource{name: "wikidata", key: func(n RelatedNode) string { return n.IDs.TMDB }, answer: func(RelatedNode) Relations {
		return Relations{Self: &RelatedNode{Wikidata: "Q477916", IDs: core.ExternalIDs{AniList: "813"}}, Edges: []RelatedEdge{}}
	}}
	byAniList := idSource{name: "anilist", key: func(n RelatedNode) string { return n.IDs.AniList }, answer: func(n RelatedNode) Relations {
		if n.IDs.AniList != "813" {
			return Relations{Edges: []RelatedEdge{}}
		}
		return Relations{
			Self:  &RelatedNode{Type: core.MediaShow, IsAnime: true, IDs: core.ExternalIDs{AniList: "813"}, Title: "Dragon Ball Z"},
			Edges: []RelatedEdge{{To: RelatedNode{Type: core.MediaShow, IsAnime: true, IDs: core.ExternalIDs{AniList: "225"}, Title: "Dragon Ball GT"}, Relation: core.RelationSequel}},
		}
	}}
	centre := RelatedNode{Type: core.MediaShow, IsAnime: true, IDs: core.ExternalIDs{TMDB: "12971"}, Title: "Dragon Ball Z"}
	graph := BuildRelationGraph(context.Background(), centre, []RelationSource{byAniList, byTMDB}, OrderRelease)
	require.Len(t, graph.Nodes, 2, "the show and its AniList entry are one title")
	require.Len(t, graph.Edges, 1)
	assert.True(t, graph.Nodes[0].Centre)
	assert.Equal(t, "813", graph.Nodes[0].IDs.AniList)
	assert.Equal(t, graph.Nodes[0].Key, graph.Edges[0].From)
}

// "Nothing related" is believed for a day, an answer with relations for a month.
func TestEmptyRelationAnswersGoStaleInADay(t *testing.T) {
	empty := Relations{Edges: []RelatedEdge{}}
	full := Relations{Edges: []RelatedEdge{{To: film("121", "The Two Towers", "2002-12-18"), Relation: core.RelationSequel}}}
	assert.True(t, relationsFresh(empty, 23*time.Hour))
	assert.False(t, relationsFresh(empty, 25*time.Hour))
	assert.True(t, relationsFresh(full, 29*24*time.Hour))
	assert.False(t, relationsFresh(full, 31*24*time.Hour))
}
