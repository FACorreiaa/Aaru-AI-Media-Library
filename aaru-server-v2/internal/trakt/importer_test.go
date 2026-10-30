package trakt

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// IMP-003: every page is read (Trakt sends 10–100 without asking); shows ask for progress.
func TestImporterReadsEveryPage(t *testing.T) {
	movies := func(page int) string {
		entries := make([]string, 5)
		for i := range entries {
			entries[i] = fmt.Sprintf(`{"movie":{"title":"M%d-%d","year":2000,"ids":{"trakt":%d}}}`, page, i, page*10+i)
		}
		return "[" + strings.Join(entries, ",") + "]"
	}
	pages := map[string][]string{
		"sync/watched/movies":   {movies(1), movies(2), movies(3)},
		"sync/watched/shows":    {`[{"show":{"title":"Severance","year":2022,"ids":{"trakt":900}},"seasons":[{"number":1,"episodes":[{"number":1}]}]}]`},
		"sync/watchlist/movies": {"[]"}, "sync/watchlist/shows": {"[]"},
		"sync/ratings/movies": {"[]"}, "sync/ratings/shows": {"[]"},
		"users/me/lists/77/items": {"[]"},
	}
	var mu sync.Mutex
	var requests []provider.Request
	transport := provider.TransportFunc(func(_ context.Context, req provider.Request) (*provider.Response, error) {
		mu.Lock()
		defer mu.Unlock()
		requests = append(requests, req)
		u, _ := url.Parse(req.URL)
		path := strings.TrimPrefix(u.Path, "/")
		if path == "users/me/lists" { // not paged: no header
			return &provider.Response{Status: 200, Body: []byte(`[{"name":"Faves","ids":{"trakt":77}}]`)}, nil
		}
		bodies, ok := pages[path]
		if !ok {
			return &provider.Response{Status: 404}, nil
		}
		page, _ := strconv.Atoi(u.Query().Get("page"))
		body := "[]"
		if page >= 1 && page <= len(bodies) {
			body = bodies[page-1]
		}
		h := http.Header{}
		h.Set("X-Pagination-Page-Count", strconv.Itoa(len(bodies)))
		return &provider.Response{Status: 200, Body: []byte(body), Header: h}, nil
	})
	api := NewAPI(Settings{ClientID: "test-client"}, transport)
	api.Client.Pacer = provider.NewPacer(1000, 100)

	rows, err := (&Importer{API: api}).Rows(context.Background(), "at-1")
	require.NoError(t, err)
	count := func(path string) (n int, first *provider.Request) {
		for i, r := range requests {
			if u, _ := url.Parse(r.URL); u.Path == "/"+path {
				if n == 0 {
					first = &requests[i]
				}
				n++
			}
		}
		return n, first
	}
	movieRows := 0
	var show *int
	for _, r := range rows {
		if r.Type == core.MediaMovie {
			movieRows++
		} else {
			n := len(r.Watched)
			show = &n
		}
	}
	assert.Equal(t, 15, movieRows, "all three pages")
	n, _ := count("sync/watched/movies")
	assert.Equal(t, 3, n)
	n, _ = count("users/me/lists")
	assert.Equal(t, 1, n, "an endpoint without paging is read once")
	_, shows := count("sync/watched/shows")
	require.NotNil(t, shows)
	u, _ := url.Parse(shows.URL)
	assert.Equal(t, "progress", u.Query().Get("extended"))
	assert.Equal(t, "250", u.Query().Get("limit"))
	require.NotNil(t, show)
	assert.Equal(t, 1, *show, "progress carries the episodes")
}

func TestReturningAppendsTheResult(t *testing.T) {
	assert.Equal(t, "aaru://settings?trakt=connected", Returning("aaru://settings", "trakt", "connected"))
	assert.Equal(t, "https://aaruapp.com/s?tab=imports&trakt=denied",
		Returning("https://aaruapp.com/s?tab=imports", "trakt", "denied"))
	assert.Equal(t, "https://aaruapp.com/s?mal=failed#top", Returning("https://aaruapp.com/s#top", "mal", "failed"))
}
