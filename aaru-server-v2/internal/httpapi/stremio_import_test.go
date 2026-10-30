package httpapi

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/stremioapi"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand/v2"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// IMP-016: a Stremio account's history through a link code, against a stub transport. No real
// Stremio account, no network (StremioImportTests).

const stremioAuthKey = "stub-session-key-never-stored"

// stremioFake is Stremio's three hosts and Cinemeta behind one transport (FakeStremio).
type stremioFake struct {
	mu       sync.Mutex
	approved bool
	library  []any
	videos   map[string][]map[string]any
	tvdb     map[string]int
	requests []provider.Request
}

func newStremioFake() *stremioFake {
	return &stremioFake{videos: map[string][]map[string]any{}, tvdb: map[string]int{}}
}

func (f *stremioFake) approve() {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.approved = true
}

func (f *stremioFake) Send(_ context.Context, req provider.Request) (*provider.Response, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.requests = append(f.requests, req)
	u, err := url.Parse(req.URL)
	if err != nil {
		return nil, err
	}
	reply := func(v any) (*provider.Response, error) {
		data, err := json.Marshal(v)
		return &provider.Response{Status: 200, Body: data}, err
	}
	switch u.Path {
	case "/api/v2/create":
		return reply(map[string]any{"result": map[string]any{
			"success": true, "code": "3AP9", "link": "https://link.stremio.com/3AP9",
			"qrcode": "https://link.stremio.com/qr?data=3AP9",
		}})
	case "/api/v2/read":
		if f.approved {
			return reply(map[string]any{"result": map[string]any{"success": true, "authKey": stremioAuthKey}})
		}
		return reply(map[string]any{"error": map[string]any{"code": 101, "message": "Invalid or expired token"}})
	case "/api/datastoreGet":
		return reply(map[string]any{"result": f.library})
	case "/api/logout":
		return reply(map[string]any{"result": map[string]any{"success": true}})
	}
	imdb := strings.TrimSuffix(strings.TrimPrefix(u.Path, "/meta/series/"), ".json")
	videos, ok := f.videos[imdb]
	if !ok {
		return &provider.Response{Status: 404}, nil
	}
	var tvdb any
	if id, ok := f.tvdb[imdb]; ok {
		tvdb = id
	}
	return reply(map[string]any{"meta": map[string]any{"videos": videos, "tvdb_id": tvdb}})
}

func (f *stremioFake) calls(path string) []provider.Request {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []provider.Request
	for _, r := range f.requests {
		if u, err := url.Parse(r.URL); err == nil && u.Path == path {
			out = append(out, r)
		}
	}
	return out
}

func (f *stremioFake) account() *stremioapi.Account {
	a := stremioapi.NewAccount(f)
	for _, c := range []*provider.Client{a.Link, a.API, a.Cinemeta} {
		c.Pacer = provider.NewPacer(1000, 100)
		c.Sleep = func(context.Context, time.Duration) error { return nil }
	}
	return a
}

func stremioIMDb() string { return fmt.Sprintf("tt%d", rand.IntN(90_000_000)+10_000_000) }

// stremioVideos is Cinemeta's list for a show with a special and two seasons of three.
func stremioVideos(imdb string) []map[string]any {
	var out []map[string]any
	for _, p := range [][2]int{{0, 1}, {1, 1}, {1, 2}, {1, 3}, {2, 1}, {2, 2}, {2, 3}} {
		out = append(out, map[string]any{
			"id": fmt.Sprintf("%s:%d:%d", imdb, p[0], p[1]), "season": p[0], "episode": p[1],
			"released": fmt.Sprintf("2020-01-0%dT00:00:00.000Z", p[1]),
		})
	}
	return out
}

func stremioLibraryItem(id, typ string, state map[string]any) map[string]any {
	return map[string]any{"_id": id, "type": typ, "name": id, "removed": false, "temp": false, "state": state}
}

func (e *libEnv) stremioStubShow(name, imdb string) {
	tmdb := e.fake.uniqueID("")
	year, st := 2020, catalog.StatusEnded
	e.fake.stubTitle(catalog.Record{
		Hit: catalog.Hit{Type: core.MediaShow, Title: name, Year: &year, IDs: core.ExternalIDs{TMDB: tmdb, IMDB: imdb}}, Status: &st,
	})
	airs := time.Now().Add(-400 * 24 * time.Hour)
	var episodes []catalog.Episode
	for season := 1; season <= 2; season++ {
		for episode := 1; episode <= 3; episode++ {
			runtime := 45
			episodes = append(episodes, catalog.Episode{Season: season, Episode: episode, AirsAt: &airs, RuntimeMinutes: &runtime})
		}
	}
	e.fake.mu.Lock()
	e.fake.episodes[tmdb] = catalog.Episodes{Status: &st, Episodes: episodes}
	e.fake.mu.Unlock()
}

func (e *libEnv) stremioStubMovie(name, imdb string) {
	year, runtime := 2020, 100
	e.fake.stubTitle(catalog.Record{
		Hit:            catalog.Hit{Type: core.MediaMovie, Title: name, Year: &year, IDs: core.ExternalIDs{TMDB: e.fake.uniqueID(""), IMDB: imdb}},
		RuntimeMinutes: &runtime,
	})
}

// stremioEntry is the user's item for the title with ids, and its ticks.
func (e *libEnv) stremioEntry(ids core.ExternalIDs, typ core.MediaType) (library.Entry, []core.EpisodeKey) {
	e.t.Helper()
	ctx := context.Background()
	title, err := e.server.Catalog.Store.Find(ctx, ids, typ)
	require.NoError(e.t, err)
	require.NotNil(e.t, title)
	entry, err := e.server.Library.Store.EntryForTitle(ctx, e.user, title.ID, time.Now())
	require.NoError(e.t, err)
	require.NotNil(e.t, entry)
	watched, err := e.server.Library.Store.WatchedSorted(ctx, entry.Item.ID)
	require.NoError(e.t, err)
	return *entry, watched
}

func appErrorOf(t *testing.T, err error) *apperr.Error {
	t.Helper()
	var appErr *apperr.Error
	require.True(t, errors.As(err, &appErr), "%v", err)
	return appErr
}

func TestStremioPendingThenApprovedReadsOnceLogsOutAndImportsTicks(t *testing.T) {
	env := newLibEnv(t)
	ctx := context.Background()
	film, show := stremioIMDb(), stremioIMDb()
	env.stremioStubMovie("Watched Film", film)
	env.stremioStubShow("Ticked Show", show)
	stremio := newStremioFake()
	stremio.library = []any{
		stremioLibraryItem(film, "movie", map[string]any{"timesWatched": 2, "lastWatched": "2024-05-01T20:00:00.000Z"}),
		stremioLibraryItem(show, "series", map[string]any{"timeOffset": 600, "watched": show + ":2:3:7:eJwTAwAAFwAX"}),
		map[string]any{"_id": 42, "type": "movie"},
	}
	stremio.videos[show] = stremioVideos(show)
	svc := env.server.Imports
	svc.Stremio = stremio.account()

	link, err := svc.StartStremioLink(ctx, env.user)
	require.NoError(t, err)
	assert.Equal(t, "3AP9", link.Code)
	assert.Equal(t, "https://link.stremio.com/3AP9", link.Link)
	pending, err := svc.PollStremioLink(ctx, "3AP9", env.user)
	require.NoError(t, err)
	assert.Nil(t, pending)
	stremio.approve()
	job, err := svc.PollStremioLink(ctx, "3AP9", env.user)
	require.NoError(t, err)
	require.NotNil(t, job)
	assert.Equal(t, core.SourceStremio, job.Source)
	assert.Len(t, stremio.calls("/api/datastoreGet"), 1)
	assert.Len(t, stremio.calls("/api/logout"), 1, "the session is logged out")
	for _, r := range stremio.requests {
		assert.Contains(t, r.Headers, [2]string{"User-Agent", stremioapi.UserAgent})
	}
	_, err = svc.PollStremioLink(ctx, "3AP9", env.user)
	assert.Equal(t, 404, appErrorOf(t, err).Status, "single use")

	env.runImports()
	planned, err := svc.Store.Rows(ctx, job.ID)
	require.NoError(t, err)
	require.Len(t, planned, 2)
	assert.Equal(t, []string{"create", "create"}, []string{string(planned[0].Outcome), string(planned[1].Outcome)})
	assert.Nil(t, planned[1].Row.StremioWatched, "the bitfield is decoded once and kept as ticks")
	env.json("POST", "/v1/imports/"+strings.ToUpper(job.ID.String())+"/apply", nil)

	movie, _ := env.stremioEntry(core.ExternalIDs{IMDB: film}, core.MediaMovie)
	assert.Equal(t, core.StatusFinished, movie.Item.Status)
	series, watched := env.stremioEntry(core.ExternalIDs{IMDB: show}, core.MediaShow)
	assert.Equal(t, core.StatusInProgress, series.Item.Status)
	assert.Equal(t, []core.EpisodeKey{{Season: 1, Episode: 1}, {Season: 1, Episode: 2}, {Season: 2, Episode: 1}}, watched)

	var mentions int
	require.NoError(t, env.pool.QueryRow(ctx, `SELECT count(*)::int FROM import_rows WHERE row::text LIKE $1`,
		"%"+stremioAuthKey+"%").Scan(&mentions))
	assert.Zero(t, mentions, "the session key is never stored")
}

func TestStremioExpiredCodeIs410AndForgottenSomeoneElsesIsNotFound(t *testing.T) {
	env := newLibEnv(t)
	ctx := context.Background()
	stremio := newStremioFake()
	svc := env.server.Imports
	svc.Stremio = stremio.account()
	now := time.Now()
	svc.Now = func() time.Time { return now }
	t.Cleanup(func() { svc.Now = nil })

	_, err := svc.StartStremioLink(ctx, env.user)
	require.NoError(t, err)
	_, err = svc.PollStremioLink(ctx, "3AP9", uuid.New())
	assert.Equal(t, 404, appErrorOf(t, err).Status)
	now = now.Add(stremioapi.LinkLifetime + time.Second)
	_, err = svc.PollStremioLink(ctx, "3AP9", env.user)
	appErr := appErrorOf(t, err)
	assert.Equal(t, 410, appErr.Status)
	assert.Equal(t, "stremio_link_expired", appErr.Code)
	assert.Equal(t, "That Stremio code expired. Start again to get a new one.", appErr.Message)
	expiry, err := svc.StremioLinkExpiry(ctx, "3AP9", env.user)
	require.NoError(t, err)
	assert.Nil(t, expiry)
	assert.Empty(t, stremio.calls("/api/v2/read"), "an expired code is not even asked about")
}

func TestStremioOverHTTPStartReturnsTheCodeAndAPendingPollIs204(t *testing.T) {
	env := newLibEnv(t)
	assert.Equal(t, 503, env.send("POST", "/v1/imports/stremio/link", nil).Code, "no account: stremio_unavailable")
	stremio := newStremioFake()
	env.server.Imports.Stremio = stremio.account()
	start := env.json("POST", "/v1/imports/stremio/link", nil)
	assert.Equal(t, "3AP9", start["code"])
	assert.Equal(t, "https://link.stremio.com/qr?data=3AP9", start["qrcode"])
	assert.NotEmpty(t, start["expiresAt"])
	assert.Equal(t, 204, env.send("POST", "/v1/imports/stremio/link/3AP9", nil).Code)
}

func TestStremioEmptyLibraryIs422(t *testing.T) {
	env := newLibEnv(t)
	stremio := newStremioFake()
	stremio.library = []any{stremioLibraryItem("tt1", "channel", map[string]any{})}
	stremio.approve()
	env.server.Imports.Stremio = stremio.account()
	env.json("POST", "/v1/imports/stremio/link", nil)
	rec := env.send("POST", "/v1/imports/stremio/link/3AP9", nil)
	assert.Equal(t, 422, rec.Code)
	body := decode[map[string]any](t, rec)
	assert.Equal(t, "Your Stremio library has no movies or shows to import.", body["message"])
	assert.Len(t, stremio.calls("/api/logout"), 1)
}

// StremioImportTests+TVDB: Bleach: Thousand-Year Blood War in a Stremio history: its own IMDb
// series in Cinemeta, which TMDB answers with a near-empty entry, while TVDB's id is Bleach's,
// where it is season 2.
func TestStremioSeriesTMDBListsApartIsImportedOntoTheTVDBShow(t *testing.T) {
	env := newLibEnv(t)
	ctx := context.Background()
	part, own := stremioIMDb(), stremioIMDb()
	tvdb := rand.IntN(900_000) + 100_000
	duplicate := env.stremioStubSplitShow(own, part, tvdb)
	stremio := newStremioFake()
	// Cinemeta: S1E1, S1E2, S2E1, S2E2 out weeks 1 to 4; the first three watched.
	for i, p := range [][2]int{{1, 1}, {1, 2}, {2, 1}, {2, 2}} {
		stremio.videos[part] = append(stremio.videos[part], map[string]any{
			"id": fmt.Sprintf("%s:%d:%d", part, p[0], p[1]), "season": p[0], "episode": p[1],
			"released": stremioWeek(i + 1).Format("2006-01-02T15:04:05.000Z07:00"),
		})
	}
	stremio.tvdb[part] = tvdb
	stremio.library = []any{
		stremioLibraryItem(part, "series", map[string]any{"timeOffset": 600, "watched": part + ":2:2:4:eJxjBwAACAAI"}),
	}
	svc := env.server.Imports
	svc.Stremio = stremio.account()
	_, err := svc.StartStremioLink(ctx, env.user)
	require.NoError(t, err)
	stremio.approve()
	job, err := svc.PollStremioLink(ctx, "3AP9", env.user)
	require.NoError(t, err)
	require.NotNil(t, job)
	env.runImports()
	env.json("POST", "/v1/imports/"+strings.ToUpper(job.ID.String())+"/apply", nil)

	_, watched := env.stremioEntry(core.ExternalIDs{IMDB: own}, core.MediaShow)
	assert.Equal(t, []core.EpisodeKey{{Season: 2, Episode: 1}, {Season: 2, Episode: 2}, {Season: 2, Episode: 3}}, watched)
	found, err := env.server.Catalog.Store.Find(ctx, core.ExternalIDs{TMDB: duplicate}, core.MediaShow)
	require.NoError(t, err)
	assert.Nil(t, found, "TMDB's near-empty entry is never stored")
}

// stremioWeek is week count after 2024-01-01.
func stremioWeek(count int) time.Time {
	return time.Unix(1_704_067_200, 0).UTC().Add(time.Duration(count) * 7 * 24 * time.Hour)
}

// stremioStubSplitShow is the show (its own IMDb id, TVDB's id, season 2 out weeks 1 to 4) and
// TMDB's one-episode entry for the part's IMDb id. It returns the entry's TMDB id.
func (e *libEnv) stremioStubSplitShow(own, part string, tvdb int) string {
	tmdb, duplicate := e.fake.uniqueID(""), e.fake.uniqueID("")
	year, st := 2004, catalog.StatusReturning
	type ep struct{ season, episode, week int }
	for _, s := range []struct {
		id, name string
		ids      core.ExternalIDs
		episodes []ep
	}{
		{tmdb, "Split Show", core.ExternalIDs{TMDB: tmdb, IMDB: own, TVDB: fmt.Sprint(tvdb)},
			[]ep{{1, 1, -39}, {1, 2, -38}, {2, 1, 1}, {2, 2, 2}, {2, 3, 3}, {2, 4, 4}}},
		{duplicate, "Split Show: Part", core.ExternalIDs{TMDB: duplicate, IMDB: part}, []ep{{1, 13, -30}}},
	} {
		e.fake.stubTitle(catalog.Record{
			Hit: catalog.Hit{Type: core.MediaShow, Title: s.name, Year: &year, IDs: s.ids, IsAnime: true}, Status: &st,
		})
		var episodes []catalog.Episode
		for _, x := range s.episodes {
			airs, runtime := stremioWeek(x.week), 24
			episodes = append(episodes, catalog.Episode{Season: x.season, Episode: x.episode, AirsAt: &airs, RuntimeMinutes: &runtime})
		}
		e.fake.mu.Lock()
		e.fake.episodes[s.id] = catalog.Episodes{Status: &st, Episodes: episodes}
		e.fake.mu.Unlock()
	}
	return duplicate
}
