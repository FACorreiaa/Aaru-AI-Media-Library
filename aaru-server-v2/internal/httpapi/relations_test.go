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

// GRAPH-001: GET /v1/titles/{id}/relations against stub TMDB and Wikidata servers.

func relationsHarness(t *testing.T) (*harness, *atomic.Int32) {
	t.Helper()
	var collectionReads atomic.Int32
	tmdb := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		films := map[string]string{
			"120": `{"id":120,"title":"The Fellowship of the Ring","release_date":"2001-12-19","poster_path":"/f.jpg","belongs_to_collection":{"id":119}}`,
			"121": `{"id":121,"title":"The Two Towers","release_date":"2002-12-18","belongs_to_collection":{"id":119}}`,
			"122": `{"id":122,"title":"The Return of the King","release_date":"2003-12-17","belongs_to_collection":{"id":119}}`,
		}
		switch r.URL.Path {
		case "/movie/120", "/movie/121", "/movie/122":
			_, _ = w.Write([]byte(films[r.URL.Path[len("/movie/"):]]))
		case "/collection/119":
			collectionReads.Add(1)
			_, _ = w.Write([]byte(`{"parts":[` + films["122"] + `,` + films["120"] + `,` + films["121"] + `]}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	wikidata := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		switch {
		case q.Get("action") == "query" && q.Get("srsearch") == "haswbstatement:P4947=120":
			_, _ = w.Write([]byte(`{"query":{"search":[{"title":"Q127367"}]}}`))
		case q.Get("action") == "query":
			_, _ = w.Write([]byte(`{"query":{"search":[]}}`))
		case q.Get("ids") == "Q127367":
			_, _ = w.Write([]byte(`{"entities":{"Q127367":{"claims":{"P144":[{"rank":"normal","mainsnak":{"datavalue":{"value":{"id":"Q208002"}}}}]}}}}`))
		case q.Get("ids") == "Q208002":
			_, _ = w.Write([]byte(`{"entities":{"Q208002":{"labels":{"en":{"value":"The Fellowship of the Ring (novel)"}},
			 "claims":{"P648":[{"rank":"normal","mainsnak":{"datavalue":{"value":"OL27448W"}}}]}}}}`))
		default:
			_, _ = w.Write([]byte(`{"entities":{}}`))
		}
	}))
	t.Cleanup(func() { tmdb.Close(); wikidata.Close() })
	client := func(name string) *provider.Client {
		c := provider.NewClient(name, provider.NewHTTPTransport(), provider.NewPacer(1000, 100))
		c.MaxAttempts = 1
		return c
	}
	providers := catalog.Providers{
		TMDB:     &catalog.TMDB{Client: client("tmdb"), APIKey: "test", BaseURL: tmdb.URL},
		AniList:  &catalog.AniList{Client: client("anilist"), Endpoint: tmdb.URL},
		Wikidata: &catalog.Wikidata{Client: client("wikidata"), Endpoint: wikidata.URL},
	}
	h := newHarness(t, func(d *Deps) { d.Catalog = catalog.NewKit(d.Pool, providers, d.Log) })
	return h, &collectionReads
}

func TestTitleRelationsRoute(t *testing.T) {
	h, collectionReads := relationsHarness(t)
	userID, bearer := h.signIn()
	rec := h.do(http.MethodPost, "/v1/titles/resolve", bearer, map[string]any{"type": "movie", "ids": map[string]string{"tmdb": "120"}})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	titleID := decode[map[string]any](t, rec)["title"].(map[string]any)["id"].(string)
	itemID := uuid.New()
	_, err := h.pool.Exec(context.Background(), `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at)
		VALUES ($1, $2, $3, 'finished', now(), now())`, itemID, userID, uuid.MustParse(titleID))
	require.NoError(t, err)

	rec = h.do(http.MethodGet, "/v1/titles/"+titleID+"/relations", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	graph := decode[map[string]any](t, rec)
	assert.Equal(t, "release", graph["order"])
	assert.Equal(t, false, graph["partial"])
	nodes := graph["nodes"].([]any)
	byTitle := map[string]map[string]any{}
	for _, n := range nodes {
		node := n.(map[string]any)
		byTitle[node["ref"].(map[string]any)["title"].(string)] = node
	}
	require.Len(t, byTitle, 4, rec.Body.String())
	fellowship := byTitle["The Fellowship of the Ring"]
	assert.Equal(t, true, fellowship["centre"])
	assert.Equal(t, "finished", fellowship["status"])
	assert.Equal(t, uuidUpper(itemID), fellowship["libraryItemId"])
	assert.InDelta(t, 0, fellowship["rank"], 0)
	towers := byTitle["The Two Towers"]
	assert.InDelta(t, 1, towers["rank"], 0)
	assert.Nil(t, towers["status"], "not in the library")
	assert.Equal(t, towers["key"], graph["startHere"], "the first one not finished")
	novel := byTitle["The Fellowship of the Ring (novel)"]
	assert.Equal(t, "book", novel["ref"].(map[string]any)["type"])
	assert.InDelta(t, 1, novel["lane"], 0)
	assert.Contains(t, graph["edges"], map[string]any{"from": novel["key"], "to": fellowship["key"], "relation": "adaptation"})

	var items int
	require.NoError(t, h.pool.QueryRow(context.Background(), `SELECT count(*) FROM library_items`).Scan(&items))
	assert.Equal(t, 1, items, "reading a graph adds nothing")

	reads := collectionReads.Load()
	require.Equal(t, http.StatusOK, h.do(http.MethodGet, "/v1/titles/"+titleID+"/relations?order=story", bearer, nil).Code)
	assert.Equal(t, reads, collectionReads.Load(), "the second graph is read from the cache")

	// GRAPH-003: Add the chain is a capture of the three films, by id, to review; nothing is added yet.
	rec = h.do(http.MethodPost, "/v1/titles/"+titleID+"/relations/chain", bearer, nil)
	require.Equal(t, http.StatusAccepted, rec.Code, rec.Body.String())
	jobID := decode[map[string]any](t, rec)["id"].(string)
	var rows int
	require.NoError(t, h.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM import_rows WHERE job_id = $1`, uuid.MustParse(jobID)).Scan(&rows))
	assert.Equal(t, 3, rows, "the main chain, not the book")
	require.NoError(t, h.pool.QueryRow(context.Background(), `SELECT count(*) FROM library_items`).Scan(&items))
	assert.Equal(t, 1, items, "planning the chain adds nothing")

	assert.Equal(t, http.StatusNotFound, h.do(http.MethodGet, "/v1/titles/"+uuid.NewString()+"/relations", bearer, nil).Code)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/titles/"+titleID+"/relations", "", nil).Code)
}

func uuidUpper(id uuid.UUID) string {
	s := id.String()
	out := make([]byte, len(s))
	for i := range len(s) {
		c := s[i]
		if c >= 'a' && c <= 'f' {
			c -= 'a' - 'A'
		}
		out[i] = c
	}
	return string(out)
}
