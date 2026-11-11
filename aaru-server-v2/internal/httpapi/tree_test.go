package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/provider"
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GRAPH-005, GRAPH-006: GET /v1/titles/{id}/tree against a stub TMDB: a film's director, its
// series, and its cast when asked for.

func treeHarness(t *testing.T) (*harness, *atomic.Int32) {
	t.Helper()
	var creditReads atomic.Int32
	films := map[string]string{
		"120": `{"id":120,"title":"The Fellowship of the Ring","release_date":"2001-12-19","poster_path":"/f.jpg","belongs_to_collection":{"id":119}}`,
		"121": `{"id":121,"title":"The Two Towers","release_date":"2002-12-18","belongs_to_collection":{"id":119}}`,
		"122": `{"id":122,"title":"The Return of the King","release_date":"2003-12-17","belongs_to_collection":{"id":119}}`,
		"254": `{"id":254,"title":"King Kong","release_date":"2005-12-12"}`,
		"603": `{"id":603,"title":"The Matrix","release_date":"1999-03-31"}`,
	}
	tmdb := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/movie/120", "/movie/121", "/movie/122", "/movie/254", "/movie/603":
			_, _ = w.Write([]byte(films[r.URL.Path[len("/movie/"):]]))
		case "/collection/119":
			_, _ = w.Write([]byte(`{"parts":[` + films["122"] + `,` + films["120"] + `,` + films["121"] + `]}`))
		case "/movie/120/credits":
			creditReads.Add(1)
			_, _ = w.Write([]byte(`{"crew":[{"id":108,"name":"Peter Jackson","job":"Director"}],"cast":[
{"id":110,"name":"Viggo Mortensen","order":1},{"id":109,"name":"Elijah Wood","order":0},{"id":111,"name":"Third Billed","order":2}]}`))
		case "/person/109/movie_credits":
			creditReads.Add(1)
			_, _ = w.Write([]byte(`{"cast":[
{"id":120,"title":"The Fellowship of the Ring","release_date":"2001-12-19","character":"Frodo","order":0,"vote_count":25000},
{"id":121,"title":"The Two Towers","release_date":"2002-12-18","character":"Frodo","order":0,"vote_count":22000},
{"id":254,"title":"King Kong","release_date":"2005-12-12","character":"A sailor","order":2,"vote_count":7000},
{"id":38,"title":"Eternal Sunshine of the Spotless Mind","release_date":"2004-03-19","character":"Patrick","order":4,"vote_count":15000},
{"id":187,"title":"Sin City","release_date":"2005-04-01","character":"Kevin","order":9,"vote_count":8000},
{"id":9806,"title":"Everything Is Illuminated","release_date":"2005-09-16","character":"Jonathan","order":0,"vote_count":600},
{"id":500,"title":"A documentary","release_date":"2006-01-01","character":"Self","order":0,"vote_count":50},
{"id":501,"title":"Happy Feet","release_date":"2006-11-16","character":"Mumble (voice)","order":0,"vote_count":5000},
{"id":502,"title":"The Good Son","release_date":"1993-09-24","character":"Mark","order":1,"vote_count":1500}]}`))
		case "/person/110/movie_credits":
			creditReads.Add(1)
			_, _ = w.Write([]byte(`{"cast":[
{"id":120,"title":"The Fellowship of the Ring","release_date":"2001-12-19","character":"Aragorn","order":1,"vote_count":25000},
{"id":38,"title":"Eternal Sunshine of the Spotless Mind","release_date":"2004-03-19","character":"A neighbour","order":3,"vote_count":15000},
{"id":59,"title":"A History of Violence","release_date":"2005-09-23","character":"Tom Stall","order":0,"vote_count":3000}]}`))
		case "/movie/603/credits":
			_, _ = w.Write([]byte(`{"crew":[]}`))
		case "/person/108/movie_credits":
			creditReads.Add(1)
			_, _ = w.Write([]byte(`{"crew":[
{"id":120,"title":"The Fellowship of the Ring","release_date":"2001-12-19","job":"Director","vote_count":25000},
{"id":121,"title":"The Two Towers","release_date":"2002-12-18","job":"Director","vote_count":22000},
{"id":122,"title":"The Return of the King","release_date":"2003-12-17","job":"Director","vote_count":24000},
{"id":254,"title":"King Kong","release_date":"2005-12-12","job":"Director","vote_count":7000,"poster_path":"/k.jpg"},
{"id":7980,"title":"The Lovely Bones","release_date":"2009-12-26","job":"Director","vote_count":3000},
{"id":49051,"title":"The Hobbit: An Unexpected Journey","release_date":"2012-12-12","job":"Director","vote_count":17000},
{"id":543580,"title":"They Shall Not Grow Old","release_date":"2018-11-09","job":"Director","vote_count":900},
{"id":1024,"title":"Heavenly Creatures","release_date":"1994-09-02","job":"Director","vote_count":800},
{"id":763,"title":"Braindead","release_date":"1992-08-13","job":"Director","vote_count":1200},
{"id":999,"title":"Undated","job":"Director","vote_count":90000}]}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	empty := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("action") == "query" {
			_, _ = w.Write([]byte(`{"query":{"search":[]}}`))
			return
		}
		_, _ = w.Write([]byte(`{"entities":{}}`))
	}))
	t.Cleanup(func() { tmdb.Close(); empty.Close() })
	client := func(name string) *provider.Client {
		c := provider.NewClient(name, provider.NewHTTPTransport(), provider.NewPacer(1000, 100))
		c.MaxAttempts = 1
		return c
	}
	providers := catalog.Providers{
		TMDB:     &catalog.TMDB{Client: client("tmdb"), APIKey: "test", BaseURL: tmdb.URL},
		AniList:  &catalog.AniList{Client: client("anilist"), Endpoint: tmdb.URL},
		Wikidata: &catalog.Wikidata{Client: client("wikidata"), Endpoint: empty.URL},
	}
	h := newHarness(t, func(d *Deps) { d.Catalog = catalog.NewKit(d.Pool, providers, d.Log) })
	return h, &creditReads
}

func TestTitleTreeRoute(t *testing.T) {
	h, creditReads := treeHarness(t)
	userID, bearer := h.signIn()
	resolve := func(tmdb string) string {
		rec := h.do(http.MethodPost, "/v1/titles/resolve", bearer, map[string]any{"type": "movie", "ids": map[string]string{"tmdb": tmdb}})
		require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
		return decode[map[string]any](t, rec)["title"].(map[string]any)["id"].(string)
	}
	add := func(titleID, status string) uuid.UUID {
		itemID := uuid.New()
		_, err := h.pool.Exec(context.Background(), `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at)
			VALUES ($1, $2, $3, $4, now(), now())`, itemID, userID, uuid.MustParse(titleID), status)
		require.NoError(t, err)
		return itemID
	}
	fellowship := resolve("120")
	rootItem := add(fellowship, "finished")
	kongItem := add(resolve("254"), "wishlist")

	rec := h.do(http.MethodGet, "/v1/titles/"+fellowship+"/tree", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	tree := decode[map[string]any](t, rec)
	assert.Equal(t, false, tree["partial"])
	root := tree["root"].(map[string]any)
	assert.Equal(t, "root", root["pick"])
	assert.Equal(t, "finished", root["status"])
	assert.Equal(t, uuidUpper(rootItem), root["libraryItemId"])
	assert.Equal(t, "The Fellowship of the Ring", root["ref"].(map[string]any)["title"])

	branches := tree["branches"].([]any)
	require.Len(t, branches, 2, rec.Body.String())
	titles := func(branch map[string]any) (names, picks []string) {
		for _, n := range branch["nodes"].([]any) {
			node := n.(map[string]any)
			names = append(names, node["ref"].(map[string]any)["title"].(string))
			picks = append(picks, node["pick"].(string))
		}
		return names, picks
	}
	director := branches[0].(map[string]any)
	assert.Equal(t, "director", director["kind"])
	assert.Equal(t, "Peter Jackson", director["label"])
	names, picks := titles(director)
	assert.Equal(t, []string{
		"King Kong", "The Lovely Bones", "The Hobbit: An Unexpected Journey", "Braindead", "They Shall Not Grow Old",
	}, names, "the next three he made, then his two best known; not the root, its sequels or the undated one")
	assert.Equal(t, []string{"next", "next", "next", "best_known", "best_known"}, picks)
	kong := director["nodes"].([]any)[0].(map[string]any)
	assert.Equal(t, "wishlist", kong["status"])
	assert.Equal(t, uuidUpper(kongItem), kong["libraryItemId"])
	assert.Equal(t, "https://image.tmdb.org/t/p/w500/k.jpg", kong["posterUrl"])
	assert.Nil(t, director["nodes"].([]any)[1].(map[string]any)["status"], "not in the library")

	series := branches[1].(map[string]any)
	assert.Equal(t, "series", series["kind"])
	assert.Nil(t, series["label"])
	names, picks = titles(series)
	assert.Equal(t, []string{"The Two Towers", "The Return of the King"}, names)
	assert.Equal(t, []string{"series", "series"}, picks)

	var items int
	require.NoError(t, h.pool.QueryRow(context.Background(), `SELECT count(*) FROM library_items`).Scan(&items))
	assert.Equal(t, 2, items, "reading a tree adds nothing")

	reads := creditReads.Load()
	assert.Equal(t, int32(2), reads, "who directed it, then his films")
	require.Equal(t, http.StatusOK, h.do(http.MethodGet, "/v1/titles/"+fellowship+"/tree", bearer, nil).Code)
	assert.Equal(t, reads, creditReads.Load(), "the second tree is read from the cache")

	// GRAPH-006: with the cast, the first two billed get a branch each after the director.
	rec = h.do(http.MethodGet, "/v1/titles/"+fellowship+"/tree?cast=true", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	tree = decode[map[string]any](t, rec)
	assert.Equal(t, false, tree["partial"])
	branches = tree["branches"].([]any)
	require.Len(t, branches, 4, rec.Body.String())
	kinds := make([]string, len(branches))
	for i, b := range branches {
		kinds[i] = b.(map[string]any)["kind"].(string)
	}
	assert.Equal(t, []string{"director", "lead_actor", "second_actor", "series"}, kinds)
	lead := branches[1].(map[string]any)
	assert.Equal(t, "Elijah Wood", lead["label"], "billed first, whatever order TMDB lists the cast in")
	names, picks = titles(lead)
	assert.Equal(t, []string{
		"Eternal Sunshine of the Spotless Mind", "Everything Is Illuminated", "Happy Feet", "The Good Son",
	}, names, "his parts: not the root or its sequels, not King Kong (the director's row has it), no cameo, nothing as himself")
	assert.Equal(t, []string{"next", "next", "next", "best_known"}, picks)
	second := branches[2].(map[string]any)
	assert.Equal(t, "Viggo Mortensen", second["label"])
	names, _ = titles(second)
	assert.Equal(t, []string{"A History of Violence"}, names, "a title the lead's row shows is not shown again")
	assert.Equal(t, reads+2, creditReads.Load(), "only the two actors' films are new reads")
	require.Equal(t, http.StatusOK, h.do(http.MethodGet, "/v1/titles/"+fellowship+"/tree?cast=true", bearer, nil).Code)
	assert.Equal(t, reads+2, creditReads.Load(), "then the cast is cached too")

	// A film with no director on record and no series has a root and no branches.
	rec = h.do(http.MethodGet, "/v1/titles/"+resolve("603")+"/tree", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.Empty(t, decode[map[string]any](t, rec)["branches"])

	assert.Equal(t, http.StatusNotFound, h.do(http.MethodGet, "/v1/titles/"+uuid.NewString()+"/tree", bearer, nil).Code)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/titles/"+fellowship+"/tree", "", nil).Code)
}
