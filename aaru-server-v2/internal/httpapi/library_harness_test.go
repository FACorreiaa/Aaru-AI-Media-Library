package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
)

// libraryFake is every catalog role from stubbed records (LibraryHarness's FakeCatalog). Test-only.
type libraryFake struct {
	mu       sync.Mutex
	titles   []catalog.Record
	episodes map[string]catalog.Episodes
	next     int
}

func (f *libraryFake) Search(context.Context, string, core.MediaType) ([]catalog.Hit, error) {
	return nil, nil
}

func (f *libraryFake) SearchMulti(context.Context, string) ([]catalog.Hit, error) { return nil, nil }

func (f *libraryFake) Hydrate(_ context.Context, ids core.ExternalIDs, mediaType core.MediaType) (*catalog.Record, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, r := range f.titles {
		if r.Hit.Type == mediaType && r.Hit.IDs.Matches(ids) {
			return &r, nil
		}
	}
	return nil, nil //nolint:nilnil // not known
}

func (f *libraryFake) Episodes(_ context.Context, ids core.ExternalIDs) (*catalog.Episodes, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, key := range []string{ids.TMDB, ids.AniList} {
		if e, ok := f.episodes[key]; key != "" && ok {
			return &e, nil
		}
	}
	return nil, nil //nolint:nilnil // not known
}

func (f *libraryFake) Tracks(context.Context, core.ExternalIDs) ([]catalog.AlbumTrack, error) {
	return nil, nil
}

func (f *libraryFake) stubTitle(r catalog.Record) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.titles = append(f.titles, r)
}

func (f *libraryFake) uniqueID(prefix string) string {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.next++
	return fmt.Sprintf("%s%d", prefix, 1000+f.next)
}

// libEnv is the LibraryHarness: HTTP tests against Postgres with a fake catalog, one signed-in user.
type libEnv struct {
	*harness
	fake   *libraryFake
	user   uuid.UUID
	bearer string
}

func newLibEnv(t *testing.T) *libEnv {
	t.Helper()
	fake := &libraryFake{episodes: map[string]catalog.Episodes{}}
	providers := catalog.Providers{TMDB: fake, AniList: fake, OpenLibrary: fake, Music: fake}
	h := newHarness(t, func(d *Deps) { d.Catalog = catalog.NewKit(d.Pool, providers, d.Log) })
	user, bearer := h.signIn()
	return &libEnv{harness: h, fake: fake, user: user, bearer: bearer}
}

func (e *libEnv) send(method, path string, body any, bearer ...string) *httptest.ResponseRecorder {
	e.t.Helper()
	token := e.bearer
	if len(bearer) > 0 {
		token = bearer[0]
	}
	return e.do(method, path, token, body)
}

func (e *libEnv) json(method, path string, body any) map[string]any {
	e.t.Helper()
	rec := e.send(method, path, body)
	require.Less(e.t, rec.Code, 300, rec.Body.String())
	return decode[map[string]any](e.t, rec)
}

// stubMovie is a movie the fake catalog can hydrate; it returns its tmdb id.
func (e *libEnv) stubMovie(name string) string {
	tmdb := e.fake.uniqueID("")
	runtime := 100
	year := 2001
	e.fake.stubTitle(catalog.Record{
		Hit: catalog.Hit{Type: core.MediaMovie, Title: name, Year: &year, IDs: core.ExternalIDs{TMDB: tmdb}}, RuntimeMinutes: &runtime,
	})
	return tmdb
}

// stubShow is a show with seasons × perSeason episodes; unaired makes the last episode of the last
// season air in the future.
func (e *libEnv) stubShow(name string, status catalog.TitleStatus, seasons, perSeason int, unaired bool) string {
	tmdb := e.fake.uniqueID("")
	year := 2020
	st := status
	e.fake.stubTitle(catalog.Record{
		Hit: catalog.Hit{Type: core.MediaShow, Title: name, Year: &year, IDs: core.ExternalIDs{TMDB: tmdb}}, Status: &st,
	})
	now := time.Now()
	var episodes []catalog.Episode
	for season := 1; season <= seasons; season++ {
		for episode := 1; episode <= perSeason; episode++ {
			airs := now.Add(-400 * 24 * time.Hour)
			if unaired && season == seasons && episode == perSeason {
				airs = now.Add(7 * 24 * time.Hour)
			}
			epName := fmt.Sprintf("S%dE%d", season, episode)
			runtime := 45
			episodes = append(episodes, catalog.Episode{
				Season: season, Episode: episode, Name: &epName, AirsAt: &airs, RuntimeMinutes: &runtime,
			})
		}
	}
	e.fake.mu.Lock()
	e.fake.episodes[tmdb] = catalog.Episodes{Status: &st, Episodes: episodes}
	e.fake.mu.Unlock()
	return tmdb
}

// add adds a title by tmdb id and returns the item's id.
func (e *libEnv) add(typ, tmdb string, status ...string) string {
	e.t.Helper()
	body := map[string]any{"mediaRef": map[string]any{"type": typ, "ids": map[string]string{"tmdb": tmdb}}}
	if len(status) > 0 {
		body["status"] = status[0]
	}
	return e.addBody(body)
}

func (e *libEnv) addBody(body map[string]any) string {
	e.t.Helper()
	rec := e.send(http.MethodPost, "/v1/library/items", body)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return decode[map[string]any](e.t, rec)["id"].(string)
}

func (e *libEnv) actionCount() int {
	e.t.Helper()
	var n int
	require.NoError(e.t, e.pool.QueryRow(context.Background(), `SELECT count(*)::int FROM actions WHERE user_id = $1`, e.user).Scan(&n))
	return n
}

// latestAction is the newest journal row's id.
func (e *libEnv) latestAction() string {
	e.t.Helper()
	items := e.json(http.MethodGet, "/v1/actions?limit=1", nil)["items"].([]any)
	require.NotEmpty(e.t, items)
	return items[0].(map[string]any)["id"].(string)
}

func (e *libEnv) watchedCount(itemID string) int {
	e.t.Helper()
	var n int
	require.NoError(e.t, e.pool.QueryRow(context.Background(),
		`SELECT count(*)::int FROM episode_progress WHERE library_item_id = $1`, uuid.MustParse(itemID)).Scan(&n))
	return n
}

func ids(items any) []string {
	var out []string
	list, _ := items.([]any)
	for _, it := range list {
		if m, ok := it.(map[string]any); ok {
			if id, ok := m["id"].(string); ok {
				out = append(out, id)
			}
		}
	}
	return out
}

func progressOf(entry map[string]any) (watched, aired float64) {
	p, _ := entry["progress"].(map[string]any)
	w, _ := p["watchedCount"].(float64)
	a, _ := p["airedCount"].(float64)
	return w, a
}
