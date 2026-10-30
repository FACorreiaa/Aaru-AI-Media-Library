package httpapi

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"context"
	"net/http"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

// searchingCatalog is libraryFake with FakeCatalog's stubSearch: a query answers the hits stubbed for it.
type searchingCatalog struct {
	*libraryFake
	mu   sync.Mutex
	hits map[string][]catalog.Hit
}

func (f *searchingCatalog) Search(_ context.Context, query string, _ core.MediaType) ([]catalog.Hit, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.hits[query], nil
}

func (f *searchingCatalog) stubSearch(query string, hits []catalog.Hit) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.hits[query] = hits
}

// scrobbleEnv is the LibraryHarness with a searchable fake catalog.
type scrobbleEnv struct {
	*libEnv
	search *searchingCatalog
}

func newScrobbleEnv(t *testing.T, tweak ...func(*Deps)) *scrobbleEnv {
	t.Helper()
	fake := &libraryFake{episodes: map[string]catalog.Episodes{}}
	search := &searchingCatalog{libraryFake: fake, hits: map[string][]catalog.Hit{}}
	providers := catalog.Providers{TMDB: search, AniList: fake, OpenLibrary: fake, Music: fake}
	all := append([]func(*Deps){func(d *Deps) { d.Catalog = catalog.NewKit(d.Pool, providers, d.Log) }}, tweak...)
	h := newHarness(t, all...)
	user, bearer := h.signIn()
	return &scrobbleEnv{libEnv: &libEnv{harness: h, fake: fake, user: user, bearer: bearer}, search: search}
}

// connect mints an agent token through the route, as the web connect page does.
func (e *libEnv) connect(kind string, extra ...map[string]any) (id, secret string) {
	e.t.Helper()
	body := map[string]any{"kind": kind}
	for _, x := range extra {
		for k, v := range x {
			body[k] = v
		}
	}
	reply := e.json(http.MethodPost, "/v1/agent/tokens", body)
	return reply["token"].(map[string]any)["id"].(string), reply["secret"].(string)
}

// caller authenticates a minted secret as the server would.
func (e *libEnv) caller(secret string, group auth.TokenGroup) auth.AgentCaller {
	e.t.Helper()
	c, ok, err := e.server.AgentTokens.Authenticate(context.Background(), secret, group)
	require.NoError(e.t, err)
	require.True(e.t, ok)
	return c
}

// titleID is the stored title with this tmdb id and type; nil when Aaru has not seen it.
func (e *libEnv) titleID(tmdb string, typ core.MediaType) *uuid.UUID {
	e.t.Helper()
	var id uuid.UUID
	err := e.pool.QueryRow(context.Background(), `SELECT id FROM titles WHERE tmdb = $1 AND type = $2`, tmdb, string(typ)).Scan(&id)
	if err != nil {
		return nil
	}
	return &id
}

// itemOf is the user's library item (id, status) for a stored title; ok false when absent.
func (e *libEnv) itemOf(tmdb string, typ core.MediaType) (id uuid.UUID, status string, ok bool) {
	e.t.Helper()
	title := e.titleID(tmdb, typ)
	if title == nil {
		return uuid.Nil, "", false
	}
	err := e.pool.QueryRow(context.Background(), `SELECT id, status FROM library_items WHERE user_id = $1 AND title_id = $2`,
		e.user, *title).Scan(&id, &status)
	return id, status, err == nil
}

// watchedKeys is an item's ticked episodes, in order.
func (e *libEnv) watchedKeys(item uuid.UUID) []core.EpisodeKey {
	e.t.Helper()
	rows, err := e.pool.Query(context.Background(),
		`SELECT season, episode FROM episode_progress WHERE library_item_id = $1 ORDER BY season, episode`, item)
	require.NoError(e.t, err)
	defer rows.Close()
	var out []core.EpisodeKey
	for rows.Next() {
		var k core.EpisodeKey
		require.NoError(e.t, rows.Scan(&k.Season, &k.Episode))
		out = append(out, k)
	}
	require.NoError(e.t, rows.Err())
	return out
}

// actions is the newest journal rows.
func (e *libEnv) actions(limit int) []map[string]any {
	e.t.Helper()
	items := e.json(http.MethodGet, "/v1/actions?limit="+itoa(limit), nil)["items"].([]any)
	out := make([]map[string]any, len(items))
	for i, it := range items {
		out[i] = it.(map[string]any)
	}
	return out
}

func key(season, episode int) core.EpisodeKey { return core.EpisodeKey{Season: season, Episode: episode} }
