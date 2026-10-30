package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/crypto"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/trakt"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// IMP-002/003 against a stubbed Trakt (TraktTests, TraktTests+API). No network, no real client id.

// traktFake is canned Trakt: routes by path (query ignored, except `page` on paged routes); an
// unknown path is a 404. It records every request.
type traktFake struct {
	mu       sync.Mutex
	routes   map[string]traktAnswer
	pages    map[string][]string
	requests []provider.Request
}

type traktAnswer struct {
	status int
	body   string
}

func newTraktFake() *traktFake {
	return &traktFake{routes: map[string]traktAnswer{}, pages: map[string][]string{}}
}

func (f *traktFake) route(path, body string, status ...int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	code := http.StatusOK
	if len(status) > 0 {
		code = status[0]
	}
	f.routes[path] = traktAnswer{status: code, body: body}
}

// routePages is a paged list, as Trakt sends it: one body per `page`, with `X-Pagination-Page-Count`.
func (f *traktFake) routePages(path string, bodies ...string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.pages[path] = bodies
}

func (f *traktFake) send(_ context.Context, req provider.Request) (*provider.Response, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.requests = append(f.requests, req)
	u, err := url.Parse(req.URL)
	if err != nil {
		return nil, err
	}
	path := strings.TrimPrefix(u.Path, "/")
	if bodies, ok := f.pages[path]; ok {
		page, _ := strconv.Atoi(u.Query().Get("page"))
		if page == 0 {
			page = 1
		}
		body := "[]"
		if page-1 < len(bodies) {
			body = bodies[page-1]
		}
		header := http.Header{}
		header.Set("X-Pagination-Page-Count", strconv.Itoa(len(bodies)))
		return &provider.Response{Status: http.StatusOK, Body: []byte(body), Header: header}, nil
	}
	answer, ok := f.routes[path]
	if !ok {
		return &provider.Response{Status: http.StatusNotFound}, nil
	}
	return &provider.Response{Status: answer.status, Body: []byte(answer.body)}, nil
}

func (f *traktFake) requestsTo(path string) []provider.Request {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []provider.Request
	for _, r := range f.requests {
		if u, err := url.Parse(r.URL); err == nil && u.Path == "/"+path {
			out = append(out, r)
		}
	}
	return out
}

func (f *traktFake) all() []provider.Request {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]provider.Request{}, f.requests...)
}

func traktQuery(req provider.Request, name string) string {
	u, _ := url.Parse(req.URL)
	return u.Query().Get(name)
}

func testCipher(t *testing.T) *crypto.TokenCipher {
	t.Helper()
	key := make([]byte, 32)
	_, err := rand.Read(key)
	require.NoError(t, err)
	cipher, err := crypto.NewTokenCipherFromKey(key)
	require.NoError(t, err)
	return cipher
}

// traktAPI is Trakt over the fake, unpaced and without retry waits.
func traktAPI(fake *traktFake, cipher *crypto.TokenCipher) *trakt.API {
	api := trakt.NewAPI(trakt.Settings{
		ClientID: "test-client", RedirectURI: "https://api.aaru.test/v1/imports/trakt/callback",
		ReturnPrefixes: []string{"aaru://", "https://web.aaru.test/"}, Cipher: cipher,
	}, provider.TransportFunc(fake.send))
	api.Client.Pacer = provider.NewPacer(1000, 100)
	api.Client.Sleep = func(context.Context, time.Duration) error { return nil }
	return api
}

type traktEnv struct {
	*libEnv
	fake   *traktFake
	cipher *crypto.TokenCipher
}

// newTraktEnv is the library harness with Trakt configured against the fake.
func newTraktEnv(t *testing.T) *traktEnv {
	t.Helper()
	env := newLibEnv(t)
	fake, cipher := newTraktFake(), testCipher(t)
	api := traktAPI(fake, cipher)
	connect := &trakt.ConnectService{Store: trakt.NewStore(env.pool), Settings: &api.Settings, API: api}
	env.server.TraktConnect = connect
	env.server.Imports.Trakt = &trakt.Source{Connect: connect, Importer: &trakt.Importer{API: api}}
	return &traktEnv{libEnv: env, fake: fake, cipher: cipher}
}

func traktTokens(access, refresh string) string {
	return fmt.Sprintf(`{"access_token":%q,"refresh_token":%q,"expires_in":7776000,"created_at":0}`, access, refresh)
}

// get sends a GET without a session (the provider's browser redirect).
func (e *traktEnv) get(path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, path, nil)
	rec := httptest.NewRecorder()
	e.echo.ServeHTTP(rec, req)
	return rec
}

// connect runs connect and the callback; it returns the callback's Location and the authorize URL.
func (e *traktEnv) connect(returnTo string) (string, *url.URL) {
	e.t.Helper()
	e.fake.route("oauth/token", traktTokens("at-123", "rt-1"))
	e.fake.route("users/settings", `{"user":{"username":"ana"}}`)
	start := e.json(http.MethodPost, "/v1/imports/trakt/connect", map[string]any{"returnTo": returnTo})
	authorize, err := url.Parse(start["authorizeUrl"].(string))
	require.NoError(e.t, err)
	state := authorize.Query().Get("state")
	rec := e.get("/v1/imports/trakt/callback?code=abc&state=" + url.QueryEscape(state))
	require.Equal(e.t, http.StatusFound, rec.Code, rec.Body.String())
	return rec.Header().Get("Location"), authorize
}

func (e *traktEnv) expire() {
	e.t.Helper()
	_, err := e.pool.Exec(context.Background(),
		`UPDATE trakt_connections SET expires_at = now() - interval '1 day' WHERE user_id = $1`, e.user)
	require.NoError(e.t, err)
}

func (e *traktEnv) connected() bool {
	e.t.Helper()
	return e.json(http.MethodGet, "/v1/imports/trakt/connection", nil)["connected"].(bool)
}

func jsonBody(t *testing.T, body []byte) map[string]string {
	t.Helper()
	var out map[string]string
	require.NoError(t, json.Unmarshal(body, &out))
	return out
}

func TestTraktConnectWithPKCE(t *testing.T) {
	env := newTraktEnv(t)
	location, authorize := env.connect("aaru://settings")
	assert.Equal(t, "aaru://settings?trakt=connected", location)
	query := authorize.Query()
	assert.Equal(t, "auth.trakt.tv", authorize.Host)
	assert.Equal(t, "test-client", query.Get("client_id"))
	assert.Equal(t, "S256", query.Get("code_challenge_method"))

	exchanges := env.fake.requestsTo("oauth/token")
	require.NotEmpty(t, exchanges)
	sent := jsonBody(t, exchanges[0].Body)
	_, hasSecret := sent["client_secret"]
	assert.False(t, hasSecret, "PKCE only: no secret, ever")
	assert.Equal(t, query.Get("code_challenge"), trakt.PKCEChallenge(sent["code_verifier"]))
	assert.Equal(t, "abc", sent["code"])

	var sealed string
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT access_token FROM trakt_connections WHERE user_id = $1`, env.user).Scan(&sealed))
	assert.NotContains(t, sealed, "at-123", "the token is never stored in clear")
	opened, err := env.cipher.Open(sealed)
	require.NoError(t, err)
	assert.Equal(t, "at-123", opened)

	status := env.json(http.MethodGet, "/v1/imports/trakt/connection", nil)
	assert.Equal(t, true, status["connected"])
	assert.Equal(t, "ana", status["username"])

	replay := env.get("/v1/imports/trakt/callback?code=abc&state=" + url.QueryEscape(query.Get("state")))
	assert.Equal(t, http.StatusBadRequest, replay.Code, "a replayed callback is refused")
	assert.Contains(t, replay.Body.String(), "trakt_state_invalid")
	evil := env.send(http.MethodPost, "/v1/imports/trakt/connect", map[string]any{"returnTo": "https://evil.test/"})
	assert.Equal(t, http.StatusUnprocessableEntity, evil.Code, "the browser only returns to Aaru")
}

func TestTraktRefreshesExpiringToken(t *testing.T) {
	env := newTraktEnv(t)
	env.connect("aaru://settings")
	env.expire()
	env.fake.route("oauth/token", traktTokens("at-fresh", "rt-2"))
	token, err := env.server.TraktConnect.AccessToken(context.Background(), env.user)
	require.NoError(t, err)
	require.NotNil(t, token)
	assert.Equal(t, "at-fresh", *token)
	refreshes := env.fake.requestsTo("oauth/token")
	sent := jsonBody(t, refreshes[len(refreshes)-1].Body)
	assert.Equal(t, "refresh_token", sent["grant_type"])
	_, hasSecret := sent["client_secret"]
	assert.False(t, hasSecret)
}

// stubTraktLibrary is four titles in the fake catalog and a Trakt library over them: Heat watched
// and rated, Severance with two episodes, Dune on the watchlist, Arrival only on the "Faves" list.
func (e *traktEnv) stubTraktLibrary() {
	year := 2000
	ended := catalog.StatusEnded
	ids := map[string]int{}
	for i, title := range []string{"Heat", "Severance", "Dune", "Arrival"} {
		id := 10_000_000 + i*7919 + int(time.Now().UnixNano()%1_000_000)
		ids[title] = id
		typ := core.MediaMovie
		var status *catalog.TitleStatus
		if title == "Severance" {
			typ, status = core.MediaShow, &ended
		}
		e.libEnv.fake.stubTitle(catalog.Record{
			Hit: catalog.Hit{Type: typ, Title: title, Year: &year, IDs: core.ExternalIDs{TMDB: strconv.Itoa(id)}}, Status: status,
		})
	}
	media := func(title string) string {
		return fmt.Sprintf(`{"title":%q,"year":2000,"ids":{"trakt":%d,"tmdb":%d}}`, title, ids[title], ids[title])
	}
	episodes := `[{"number":1,"episodes":[{"number":1},{"number":2}]}]`
	e.fake.route("sync/watched/movies", `[{"last_watched_at":"2024-02-01T20:00:00.000Z","movie":`+media("Heat")+`}]`)
	e.fake.route("sync/watched/shows", `[{"show":`+media("Severance")+`,"seasons":`+episodes+`}]`)
	e.fake.route("sync/watchlist/movies", `[{"type":"movie","movie":`+media("Dune")+`}]`)
	e.fake.route("sync/watchlist/shows", "[]")
	e.fake.route("sync/ratings/movies", `[{"type":"movie","rating":9,"movie":`+media("Heat")+`}]`)
	e.fake.route("sync/ratings/shows", "[]")
	e.fake.route("users/me/lists", `[{"name":"Faves","ids":{"trakt":77}}]`)
	e.fake.route("users/me/lists/77/items",
		`[{"type":"movie","movie":`+media("Heat")+`},{"type":"movie","movie":`+media("Arrival")+`}]`)
}

// planTrakt queues a Trakt import, runs the worker until it leaves the queue, and returns the job
// and its rows.
func (e *traktEnv) planTrakt() (string, map[string]any, []map[string]any) {
	e.t.Helper()
	created := e.send(http.MethodPost, "/v1/imports/trakt", nil)
	require.Equal(e.t, http.StatusAccepted, created.Code, created.Body.String())
	id := decode[map[string]any](e.t, created)["id"].(string)
	e.runImports()
	job, rows := e.importDetail(id)
	return id, job, rows
}

func TestTraktImportPlansThenApplies(t *testing.T) {
	env := newTraktEnv(t)
	env.connect("aaru://settings")
	env.stubTraktLibrary()

	id, _, rows := env.planTrakt()
	outcomes := map[string]string{}
	for _, r := range rows {
		outcomes[r["title"].(string)] = r["outcome"].(string)
	}
	assert.Equal(t, map[string]string{"Heat": "create", "Severance": "create", "Dune": "create", "Arrival": "skip"}, outcomes)

	applied := env.send(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
	require.Equal(t, http.StatusOK, applied.Code, applied.Body.String())
	items := env.json(http.MethodGet, "/v1/library/sync", nil)["items"].([]any)
	byTitle := map[string]map[string]any{}
	for _, it := range items {
		m := it.(map[string]any)
		byTitle[m["title"].(map[string]any)["title"].(string)] = m
	}
	assert.Equal(t, "finished", byTitle["Heat"]["status"])
	assert.InDelta(t, 9.0, byTitle["Heat"]["rating"], 0.001)
	assert.Equal(t, "wishlist", byTitle["Dune"]["status"])
	assert.NotContains(t, byTitle, "Arrival", "a list-only title does not join the library")
	show := env.json(http.MethodGet, "/v1/library/items/"+byTitle["Severance"]["id"].(string), nil)
	assert.Len(t, show["watchedEpisodes"], 2)
	lists := env.json(http.MethodGet, "/v1/lists", nil)["items"].([]any)
	var faves map[string]any
	for _, l := range lists {
		if m := l.(map[string]any); m["name"] == "Faves" {
			faves = m
		}
	}
	require.NotNil(t, faves)
	assert.InDelta(t, 2.0, faves["itemCount"], 0.001, "Heat and the list-only Arrival")
}

func traktReadPaths() []string {
	return []string{
		"sync/watched/movies", "sync/watched/shows", "sync/watchlist/movies", "sync/watchlist/shows",
		"sync/ratings/movies", "sync/ratings/shows", "users/me/lists",
	}
}

func TestTraktRevokedTokenFailsAndDisconnects(t *testing.T) {
	env := newTraktEnv(t)
	env.connect("aaru://settings")
	for _, path := range traktReadPaths() {
		env.fake.route(path, "{}", http.StatusUnauthorized)
	}
	_, job, _ := env.planTrakt()
	assert.Equal(t, "failed", job["state"])
	assert.Contains(t, job["errorSummary"], "Connect Trakt again")
	assert.False(t, env.connected())
}

func TestTraktNotConfigured(t *testing.T) {
	env := newLibEnv(t)
	reply := env.send(http.MethodPost, "/v1/imports/trakt/connect", map[string]any{"returnTo": "aaru://settings"})
	assert.Equal(t, http.StatusServiceUnavailable, reply.Code)
	assert.Contains(t, reply.Body.String(), "trakt_unavailable")
	assert.Equal(t, http.StatusConflict, env.send(http.MethodPost, "/v1/imports/trakt", nil).Code)
}

func TestTraktHostsAndHeaders(t *testing.T) {
	env := newTraktEnv(t)
	env.connect("aaru://settings")
	env.stubTraktLibrary()
	env.planTrakt()
	all := env.fake.all()
	assert.Greater(t, len(all), 5)
	for _, req := range all {
		headers := map[string]string{}
		for _, h := range req.Headers {
			if _, seen := headers[h[0]]; !seen {
				headers[h[0]] = h[1]
			}
		}
		assert.Equal(t, trakt.UserAgent, headers["User-Agent"], req.URL)
		assert.Equal(t, "test-client", headers["trakt-api-key"])
		u, err := url.Parse(req.URL)
		require.NoError(t, err)
		want := "api.trakt.tv"
		if strings.HasPrefix(u.Path, "/oauth/") {
			want = "auth.trakt.tv"
		}
		assert.Equal(t, want, u.Host, req.URL)
	}
}

func TestTraktRefreshesOnce(t *testing.T) {
	env := newTraktEnv(t)
	env.connect("aaru://settings")
	env.expire()
	env.fake.route("oauth/token", traktTokens("at-fresh", "rt-2"))
	before := len(env.fake.requestsTo("oauth/token"))
	var wg sync.WaitGroup
	tokens := make([]string, 2)
	errs := make([]error, 2)
	for i := range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			token, err := env.server.TraktConnect.AccessToken(context.Background(), env.user)
			errs[i] = err
			if token != nil {
				tokens[i] = *token
			}
		}()
	}
	wg.Wait()
	require.NoError(t, errs[0])
	require.NoError(t, errs[1])
	assert.Equal(t, []string{"at-fresh", "at-fresh"}, tokens)
	assert.Equal(t, 1, len(env.fake.requestsTo("oauth/token"))-before)
}

func TestTraktRefusedRefreshFailsAndDisconnects(t *testing.T) {
	env := newTraktEnv(t)
	env.connect("aaru://settings")
	env.expire()
	env.fake.route("oauth/token", `{"error":"invalid_grant","error_description":"session not found"}`, http.StatusBadRequest)
	_, job, _ := env.planTrakt()
	assert.Equal(t, "failed", job["state"])
	assert.Contains(t, job["errorSummary"], "Connect Trakt again")
	assert.False(t, env.connected())
}

func TestTraktAccountLimit(t *testing.T) {
	env := newTraktEnv(t)
	env.connect("aaru://settings")
	env.stubTraktLibrary()
	env.fake.route("sync/watched/movies", "{}", 420)
	_, job, _ := env.planTrakt()
	assert.Equal(t, "failed", job["state"])
	assert.Contains(t, job["errorSummary"], "Trakt's limits")
	assert.Len(t, env.fake.requestsTo("sync/watched/movies"), 1, "not retried")
	assert.True(t, env.connected())
}

func TestTraktDisconnectRevokes(t *testing.T) {
	env := newTraktEnv(t)
	env.connect("aaru://settings")
	env.fake.route("oauth/revoke", "")
	assert.Less(t, env.send(http.MethodDelete, "/v1/imports/trakt/connection", nil).Code, 300)
	revokes := env.fake.requestsTo("oauth/revoke")
	require.NotEmpty(t, revokes)
	assert.Equal(t, map[string]string{"token": "at-123", "client_id": "test-client"}, jsonBody(t, revokes[0].Body))
	assert.False(t, env.connected())

	env.connect("aaru://settings")
	env.fake.route("oauth/revoke", "", http.StatusServiceUnavailable)
	assert.Less(t, env.send(http.MethodDelete, "/v1/imports/trakt/connection", nil).Code, 300)
	assert.False(t, env.connected())
}
