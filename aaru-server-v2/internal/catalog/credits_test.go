package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GRAPH-005: each credit source against canned JSON, and the branches cut from a relation graph.

func TestTMDBCreditsReadAFilmsDirectorAndTheirFilms(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		switch strings.TrimPrefix(urlPath(req.URL), "/3") {
		case "/movie/329865/credits":
			return provider.Response{Status: 200, Body: []byte(`{"crew":[
{"id":1,"name":"Bradford Young","job":"Director of Photography"},
{"id":137427,"name":"Denis Villeneuve","job":"Director"},
{"id":2,"name":"Second Unit","job":"Director"}]}`)}
		case "/person/137427/movie_credits":
			return provider.Response{Status: 200, Body: []byte(`{"cast":[{"id":7,"title":"A cameo"}],"crew":[
{"id":329865,"title":"Arrival","release_date":"2016-11-10","job":"Director","vote_count":18000},
{"id":335984,"title":"Blade Runner 2049","release_date":"2017-10-04","job":"Director","vote_count":14000,"poster_path":"/b.jpg"},
{"id":335984,"title":"Blade Runner 2049","release_date":"2017-10-04","job":"Writer","vote_count":14000},
{"id":438631,"title":"Dune","release_date":"2021-09-15","job":"Director","vote_count":13000},
{"id":438631,"title":"Dune","release_date":"2021-09-15","job":"Director","vote_count":13000},
{"id":8,"title":"Making of Dune","release_date":"2021-10-01","job":"Director","video":true},
{"id":9,"title":"Not for here","release_date":"2001-01-01","job":"Director","adult":true},
{"id":10,"title":"Produced only","release_date":"2020-01-01","job":"Producer"}]}`)}
		case "/movie/1/credits":
			return provider.Response{Status: 200, Body: []byte(`{"crew":[]}`)}
		}
		return provider.Response{Status: 404, Body: []byte(`{}`)}
	})
	tmdb := &TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}
	arrival := film("329865", "Arrival", "2016-11-10")
	assert.Equal(t, "movie:329865", tmdb.CreditKey(arrival))

	people, err := tmdb.People(context.Background(), arrival)
	require.NoError(t, err)
	require.Equal(t, []Credit{{Kind: core.BranchDirector, ID: "137427", Name: "Denis Villeneuve"}}, people)

	works, err := tmdb.Works(context.Background(), people[0])
	require.NoError(t, err)
	require.Len(t, works, 3, "directed films only, once each, no extras and no adult titles")
	assert.Equal(t, "Blade Runner 2049", works[1].Title)
	assert.Equal(t, 14000, works[1].Score)
	assert.Equal(t, "2017-10-04", *works[1].ReleaseDate)
	assert.Equal(t, "https://image.tmdb.org/t/p/w500/b.jpg", *works[1].PosterURL)
	assert.Equal(t, core.MediaMovie, works[1].Type)

	none, err := tmdb.People(context.Background(), film("1", "No director", "2000-01-01"))
	require.NoError(t, err)
	assert.Empty(t, none)
	missing, err := tmdb.People(context.Background(), film("404", "Gone", "2000-01-01"))
	require.NoError(t, err)
	assert.Empty(t, missing)
	assert.Empty(t, tmdb.CreditKey(book("OL1W", "A book", 2000)))
}

func TestTMDBCreditsReadAShowsCreatorAndTheirShows(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		switch strings.TrimPrefix(urlPath(req.URL), "/3") {
		case "/tv/1396":
			return provider.Response{Status: 200, Body: []byte(`{"id":1396,"name":"Breaking Bad","created_by":[{"id":66633,"name":"Vince Gilligan"}]}`)}
		case "/person/66633/tv_credits":
			return provider.Response{Status: 200, Body: []byte(`{"crew":[
{"id":1396,"name":"Breaking Bad","first_air_date":"2008-01-20","job":"Creator","vote_count":15000},
{"id":60059,"name":"Better Call Saul","first_air_date":"2015-02-08","job":"Creator","vote_count":6000},
{"id":4087,"name":"The X-Files","first_air_date":"1993-09-10","job":"Executive Producer","vote_count":4000}]}`)}
		}
		return provider.Response{Status: 404, Body: []byte(`{}`)}
	})
	tmdb := &TMDB{Client: testClient(stub, "tmdb"), APIKey: "k"}
	show := RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: "1396"}, Title: "Breaking Bad"}
	assert.Equal(t, "tv:1396", tmdb.CreditKey(show))
	people, err := tmdb.People(context.Background(), show)
	require.NoError(t, err)
	require.Equal(t, []Credit{{Kind: core.BranchCreator, ID: "66633", Name: "Vince Gilligan"}}, people)
	works, err := tmdb.Works(context.Background(), people[0])
	require.NoError(t, err)
	require.Len(t, works, 2, "shows they created, not ones they produced")
	assert.Equal(t, core.MediaShow, works[1].Type)
	assert.Equal(t, "Better Call Saul", works[1].Title)
}

func TestAniListCreditsReadAStudioAndAnAuthor(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		body := string(req.Body)
		switch {
		case strings.Contains(body, "studios(isMain: true)") && strings.Contains(body, `"id":16498`):
			return provider.Response{Status: 200, Body: []byte(`{"data":{"Media":{"type":"ANIME",
"studios":{"nodes":[{"id":858,"name":"WIT STUDIO"}]},"staff":{"edges":[{"role":"Director","node":{"id":1,"name":{"full":"Someone"}}}]}}}}`)}
		case strings.Contains(body, "studios(isMain: true)") && strings.Contains(body, `"id":30002`):
			return provider.Response{Status: 200, Body: []byte(`{"data":{"Media":{"type":"MANGA","studios":{"nodes":[]},
"staff":{"edges":[
 {"role":"Translator (English)","node":{"id":3,"name":{"full":"A Translator"}}},
 {"role":"Art","node":{"id":4,"name":{"full":"An Artist"}}},
 {"role":"Story & Art (vols 1-41)","node":{"id":96868,"name":{"full":"Kentarou Miura"}}}]}}}}`)}
		case strings.Contains(body, "Studio(id: $id)"):
			return provider.Response{Status: 200, Body: []byte(`{"data":{"Studio":{"media":{"nodes":[
 {"id":16498,"type":"ANIME","format":"TV","popularity":1000,"title":{"english":"Attack on Titan"},"startDate":{"year":2013,"month":4,"day":7}},
 {"id":101348,"type":"ANIME","format":"TV","popularity":600,"title":{"english":"Vinland Saga"},"startDate":{"year":2019,"month":7,"day":8}},
 {"id":18397,"type":"ANIME","format":"OVA","popularity":300,"title":{"romaji":"An OVA"}},
 {"id":5,"type":"ANIME","format":"MOVIE","popularity":200,"isAdult":true,"title":{"romaji":"Adult"}},
 {"id":6,"type":"ANIME","format":"MOVIE","popularity":100,"title":{"romaji":"A film"},"startDate":{"year":2022}}]}}}}`)}
		case strings.Contains(body, "staffMedia(type: MANGA"):
			return provider.Response{Status: 200, Body: []byte(`{"data":{"Staff":{"staffMedia":{"edges":[
 {"staffRole":"Story & Art","node":{"id":30002,"type":"MANGA","format":"MANGA","popularity":900,"title":{"english":"Berserk"},"startDate":{"year":1989,"month":8,"day":25}}},
 {"staffRole":"Art","node":{"id":31,"type":"MANGA","format":"MANGA","popularity":50,"title":{"romaji":"Japan"},"startDate":{"year":1992}}},
 {"staffRole":"Story","node":{"id":31,"type":"MANGA","format":"MANGA","popularity":50,"title":{"romaji":"Japan"},"startDate":{"year":1992}}},
 {"staffRole":"Assistant","node":{"id":32,"type":"MANGA","format":"MANGA","popularity":70,"title":{"romaji":"Someone else's"}}}]}}}}`)}
		}
		return provider.Response{Status: 200, Body: []byte(`{"data":null}`)}
	})
	a := &AniList{Client: testClient(stub, "anilist")}
	ctx := context.Background()

	studio, err := a.People(ctx, RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{AniList: "16498"}})
	require.NoError(t, err)
	require.Equal(t, []Credit{{Kind: core.BranchStudio, ID: "858", Name: "WIT STUDIO"}}, studio)
	works, err := a.Works(ctx, studio[0])
	require.NoError(t, err)
	require.Len(t, works, 3, "series and films, no OVA and nothing adult")
	assert.Equal(t, "Vinland Saga", works[1].Title)
	assert.Equal(t, 600, works[1].Score)
	assert.Equal(t, "101348", works[1].IDs.AniList)
	assert.Equal(t, core.MediaMovie, works[2].Type)

	author, err := a.People(ctx, RelatedNode{Type: core.MediaManga, IDs: core.ExternalIDs{AniList: "30002"}})
	require.NoError(t, err)
	require.Equal(t, []Credit{{Kind: core.BranchAuthor, ID: "96868", Name: "Kentarou Miura"}}, author,
		"who wrote it comes before who drew it")
	works, err = a.Works(ctx, author[0])
	require.NoError(t, err)
	require.Len(t, works, 2, "their own manga, once each")
	assert.Equal(t, core.MediaManga, works[0].Type)

	gone, err := a.People(ctx, RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{AniList: "1"}})
	require.NoError(t, err)
	assert.Empty(t, gone)
	assert.Empty(t, a.CreditKey(RelatedNode{Type: core.MediaShow, IDs: core.ExternalIDs{TMDB: "1429"}}))
}

func TestOpenLibraryCreditsReadTheAuthorByKey(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		q := urlQuery(req.URL)
		switch q.Get("q") {
		case "key:/works/OL893414W":
			return provider.Response{Status: 200, Body: []byte(`{"docs":[{"key":"/works/OL893414W","author_key":["OL79034A","OL2A"],"author_name":["Frank Herbert","Another"]}]}`)}
		case "author_key:OL79034A":
			assert.Equal(t, "readinglog", q.Get("sort"))
			return provider.Response{Status: 200, Body: []byte(`{"docs":[
{"key":"/works/OL893414W","title":"Dune","first_publish_year":1965,"cover_i":1,"readinglog_count":4504},
{"key":"/works/OL893461W","title":"Dune Messiah","first_publish_year":1969,"cover_i":2,"readinglog_count":879},
{"key":"/works/OL3W","title":"No cover","first_publish_year":1970,"readinglog_count":5},
{"key":"/authors/OL79034A","title":"Not a work","cover_i":3}]}`)}
		}
		return provider.Response{Status: 200, Body: []byte(`{"docs":[]}`)}
	})
	o := &OpenLibrary{Client: testClient(stub, "openlibrary")}
	dune := book("OL893414W", "Dune", 1965)
	assert.Equal(t, "work:OL893414W", o.CreditKey(dune))
	people, err := o.People(context.Background(), dune)
	require.NoError(t, err)
	require.Equal(t, []Credit{{Kind: core.BranchAuthor, ID: "OL79034A", Name: "Frank Herbert"}}, people)
	works, err := o.Works(context.Background(), people[0])
	require.NoError(t, err)
	require.Len(t, works, 2, "works with a cover")
	assert.Equal(t, "OL893461W", works[1].IDs.OpenLibrary)
	assert.Equal(t, 879, works[1].Score)
	assert.Equal(t, 1969, *works[1].Year)
	assert.Nil(t, works[1].ReleaseDate, "Open Library knows the year only")

	unknown, err := o.People(context.Background(), book("OL0W", "Unknown", 2000))
	require.NoError(t, err)
	assert.Empty(t, unknown)
}

func TestMusicBrainzCreditsReadTheArtistsStudioAlbums(t *testing.T) {
	stub := stubFunc(func(req provider.Request) provider.Response {
		q := urlQuery(req.URL)
		switch {
		case strings.HasSuffix(urlPath(req.URL), "/release-group/rg-ok"):
			return provider.Response{Status: 200, Body: []byte(`{"id":"rg-ok","title":"OK Computer","primary-type":"Album",
"artist-credit":[{"name":"Radiohead","artist":{"id":"A74B1B7F","name":"Radiohead"}}]}`)}
		case strings.HasSuffix(urlPath(req.URL), "/release-group/rg-va"):
			return provider.Response{Status: 200, Body: []byte(`{"id":"rg-va","title":"Hits","primary-type":"Album",
"artist-credit":[{"name":"Various Artists","artist":{"id":"89ad4ac3-39f7-470e-963a-56509c546377","name":"Various Artists"}}]}`)}
		case strings.HasSuffix(urlPath(req.URL), "/release-group"):
			assert.Contains(t, q.Get("query"), "arid:a74b1b7f")
			assert.Contains(t, q.Get("query"), "NOT secondarytype:*")
			return provider.Response{Status: 200, Body: []byte(`{"release-groups":[
{"id":"rg-kid-a","title":"Kid A","primary-type":"Album","first-release-date":"2000-08-03"},
{"id":"rg-ep","title":"Airbag / How Am I Driving?","primary-type":"EP","first-release-date":"1998"},
{"id":"rg-single","title":"Creep","primary-type":"Single","first-release-date":"1992-09-21"}]}`)}
		}
		return provider.Response{Status: 404, Body: []byte(`{}`)}
	})
	m := &MusicBrainz{Client: testClient(stub, "musicbrainz")}
	album := RelatedNode{Type: core.MediaAlbum, IDs: core.ExternalIDs{MusicBrainz: "rg-ok"}, Title: "OK Computer"}
	assert.Equal(t, "release-group:rg-ok", m.CreditKey(album))
	people, err := m.People(context.Background(), album)
	require.NoError(t, err)
	require.Equal(t, []Credit{{Kind: core.BranchArtist, ID: "a74b1b7f", Name: "Radiohead"}}, people)
	works, err := m.Works(context.Background(), people[0])
	require.NoError(t, err)
	require.Len(t, works, 2, "albums and EPs, not singles")
	assert.Equal(t, "2000-08-03", *works[0].ReleaseDate)
	assert.Zero(t, works[0].Score, "MusicBrainz has no count")
	assert.Equal(t, 1998, *works[1].Year)

	various, err := m.People(context.Background(), RelatedNode{Type: core.MediaAlbum, IDs: core.ExternalIDs{MusicBrainz: "rg-va"}})
	require.NoError(t, err)
	assert.Empty(t, various, "Various Artists is not a person")
}

func TestGraphBranchesCutTheSeriesAndTheAdaptations(t *testing.T) {
	node := func(key string, rank int, chain, centre bool, n RelatedNode) GraphNode {
		return GraphNode{RelatedNode: n, Key: key, Rank: rank, MainChain: chain, Centre: centre}
	}
	graph := RelationGraph{
		Nodes: []GraphNode{
			node("hobbit", 0, true, false, film("1", "An earlier film", "1999-01-01")),
			node("fellowship", 1, true, true, film("120", "The Fellowship of the Ring", "2001-12-19")),
			node("towers", 2, true, false, film("121", "The Two Towers", "2002-12-18")),
			node("king", 3, true, false, film("122", "The Return of the King", "2003-12-17")),
			node("novel", 1, false, false, book("OL27448W", "The Fellowship of the Ring", 1954)),
			node("game", 1, false, false, book("OL9W", "A side story", 2004)),
		},
		Edges: []GraphEdge{
			{From: "fellowship", To: "towers", Relation: core.RelationSequel},
			{From: "novel", To: "fellowship", Relation: core.RelationAdaptation},
			{From: "novel", To: "fellowship", Relation: core.RelationAdaptation},
			{From: "fellowship", To: "game", Relation: core.RelationSideStory},
		},
	}
	branches := graphBranches(graph)
	require.Len(t, branches, 2)
	assert.Equal(t, core.BranchSeries, branches[0].Kind)
	require.Len(t, branches[0].Nodes, 2, "what comes after the centre, not what came before")
	assert.Equal(t, "The Two Towers", branches[0].Nodes[0].Title)
	assert.Equal(t, core.PickSeries, branches[0].Nodes[0].Pick)
	assert.Equal(t, core.BranchAdaptation, branches[1].Kind)
	require.Len(t, branches[1].Nodes, 1, "once, and not the side story")
	assert.Equal(t, core.MediaBook, branches[1].Nodes[0].Type)

	assert.Empty(t, graphBranches(RelationGraph{Nodes: []GraphNode{node("alone", 0, true, true, film("603", "The Matrix", "1999-03-31"))}}))
	assert.Empty(t, graphBranches(RelationGraph{}))
}
