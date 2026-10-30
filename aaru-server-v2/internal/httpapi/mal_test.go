package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/crypto"
	"aaru-go-api/internal/mal"
	"aaru-go-api/internal/provider"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// SCR-005 and SCR-010 against a stubbed MyAnimeList (MALTests, MALTests+Fake, MALPullTests). No
// network, no real client id.

// malFake is canned MAL: token, user, list and list-status routes. It records every request.
type malFake struct {
	mu          sync.Mutex
	patchStatus int
	list        []map[string]any
	listStatus  int
	requests    []provider.Request
}

type malPatch struct {
	malID  string
	fields map[string]string
}

func newMALFake() *malFake { return &malFake{patchStatus: 200, listStatus: 200} }

func (f *malFake) failPatches(status int) { f.mu.Lock(); f.patchStatus = status; f.mu.Unlock() }
func (f *malFake) failList(status int)    { f.mu.Lock(); f.listStatus = status; f.mu.Unlock() }
func (f *malFake) setList(entries ...map[string]any) {
	f.mu.Lock()
	f.list = entries
	f.mu.Unlock()
}

func (f *malFake) send(_ context.Context, req provider.Request) (*provider.Response, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.requests = append(f.requests, req)
	u, err := url.Parse(req.URL)
	if err != nil {
		return nil, err
	}
	switch u.Path {
	case "/v2/users/@me/animelist":
		return f.listPage(u.Query()), nil
	case "/v1/oauth2/token":
		body := `{"token_type":"Bearer","expires_in":2678400,"access_token":"at-1","refresh_token":"rt-1"}`
		return &provider.Response{Status: 200, Body: []byte(body)}, nil
	case "/v2/users/@me":
		return &provider.Response{Status: 200, Body: []byte(`{"id":1,"name":"ana"}`)}, nil
	}
	if req.Method != http.MethodPatch || !strings.HasSuffix(u.Path, "/my_list_status") {
		return &provider.Response{Status: 404}, nil
	}
	return &provider.Response{Status: f.patchStatus, Body: []byte("{}")}, nil
}

// listPage is one page by `offset` and `limit`, with `paging.next` while entries remain.
func (f *malFake) listPage(query url.Values) *provider.Response {
	if f.listStatus != 200 {
		return &provider.Response{Status: f.listStatus}
	}
	offset, _ := strconv.Atoi(query.Get("offset"))
	limit, _ := strconv.Atoi(query.Get("limit"))
	limit = max(limit, 1)
	data := []map[string]any{}
	for i := offset; i < len(f.list) && i < offset+limit; i++ {
		data = append(data, f.list[i])
	}
	body := map[string]any{"data": data, "paging": map[string]any{}}
	if offset+limit < len(f.list) {
		body["paging"] = map[string]any{"next": fmt.Sprintf("https://api.myanimelist.net/v2/users/@me/animelist?offset=%d", offset+limit)}
	}
	encoded, _ := json.Marshal(body)
	return &provider.Response{Status: 200, Body: encoded}
}

// patches are every list write, oldest first: the MAL id and its form fields.
func (f *malFake) patches() []malPatch {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []malPatch
	for _, r := range f.requests {
		if r.Method != http.MethodPatch {
			continue
		}
		parts := strings.Split(r.URL, "/")
		out = append(out, malPatch{malID: parts[len(parts)-2], fields: malForm(r.Body)})
	}
	return out
}

func (f *malFake) firstBody(path string) []byte {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, r := range f.requests {
		if u, err := url.Parse(r.URL); err == nil && u.Path == path {
			return r.Body
		}
	}
	return nil
}

func malForm(body []byte) map[string]string {
	values, _ := url.ParseQuery(string(body))
	out := map[string]string{}
	for k, v := range values {
		out[k] = v[len(v)-1]
	}
	return out
}

func malAPI(fake *malFake, cipher *crypto.TokenCipher, secret *string) *mal.API {
	api := mal.NewAPI(mal.Settings{
		ClientID: "test-client", ClientSecret: secret, RedirectURI: "https://api.aaru.test/v1/connections/mal/callback",
		ReturnPrefixes: []string{"aaru://", "https://web.aaru.test/"}, Cipher: cipher,
	}, provider.TransportFunc(fake.send))
	api.Client.Pacer = provider.NewPacer(1000, 100)
	api.Client.Sleep = func(context.Context, time.Duration) error { return nil }
	return api
}

type malEnv struct {
	*traktEnv
	mal    *malFake
	cipher *crypto.TokenCipher
}

// newMALEnv is the library harness with MyAnimeList configured against the fake.
func newMALEnv(t *testing.T, secret ...string) *malEnv {
	t.Helper()
	env := newLibEnv(t)
	fake, cipher := newMALFake(), testCipher(t)
	var s *string
	if len(secret) > 0 {
		s = &secret[0]
	}
	api := malAPI(fake, cipher, s)
	env.server.MALConnect = &mal.ConnectService{Store: mal.NewStore(env.pool), Settings: &api.Settings, API: api}
	return &malEnv{traktEnv: &traktEnv{libEnv: env}, mal: fake, cipher: cipher}
}

func (e *malEnv) pusher() *mal.Pusher {
	c := e.server.MALConnect
	return &mal.Pusher{Store: c.Store, Connect: c, API: c.API, Library: e.server.Library.Store, Catalog: e.server.Catalog.Store}
}

func (e *malEnv) puller() *mal.Puller {
	c := e.server.MALConnect
	return &mal.Puller{Store: c.Store, Connect: c, Imports: e.server.Imports, API: c.API}
}

func (e *malEnv) push() int {
	e.t.Helper()
	n, err := e.pusher().RunOnce(context.Background())
	require.NoError(e.t, err)
	return n
}

func (e *malEnv) pull(cursor time.Time, full bool) int {
	e.t.Helper()
	n, err := e.puller().Pull(context.Background(), mal.PullDue{UserID: e.user, Cursor: cursor, FullRead: full})
	require.NoError(e.t, err)
	return n
}

// connectMAL runs connect and the callback; it returns the callback's Location and the authorize URL.
func (e *malEnv) connectMAL() (string, *url.URL) {
	e.t.Helper()
	start := e.json(http.MethodPost, "/v1/connections/mal/connect", map[string]any{"returnTo": "aaru://settings"})
	authorize, err := url.Parse(start["authorizeUrl"].(string))
	require.NoError(e.t, err)
	rec := e.get("/v1/connections/mal/callback?code=abc&state=" + url.QueryEscape(authorize.Query().Get("state")))
	require.Equal(e.t, http.StatusFound, rec.Code, rec.Body.String())
	return rec.Header().Get("Location"), authorize
}

func (e *malEnv) malStatus() map[string]any {
	e.t.Helper()
	return e.json(http.MethodGet, "/v1/connections/mal", nil)
}

func malUniqueID() string { return strconv.Itoa(10_000_000 + int(uuid.New().ID()%900_000_000)) }

func (e *malEnv) mapSeason(tmdb, malID string, season int) {
	e.t.Helper()
	anilist, s := "al"+malUniqueID(), season
	require.NoError(e.t, e.server.Catalog.Store.UpsertMapping(context.Background(), catalog.AnimeMapping{
		AniList: anilist, MAL: &malID, TMDB: &tmdb, TMDBSeason: &s,
	}))
}

// anime is a two-season anime (3 episodes each) whose seasons map to the given MAL entries.
func (e *malEnv) anime(seasons map[int][]string, status ...string) (string, string) {
	e.t.Helper()
	tmdb := e.stubShow("Frieren", catalog.StatusEnded, 2, 3, false)
	for season, ids := range seasons {
		for _, id := range ids {
			e.mapSeason(tmdb, id, season)
		}
	}
	st := "in_progress"
	if len(status) > 0 {
		st = status[0]
	}
	return tmdb, e.add("show", tmdb, st)
}

func (e *malEnv) tick(item string, season, episode int) {
	e.t.Helper()
	rec := e.send(http.MethodPut, fmt.Sprintf("/v1/library/items/%s/episodes/%d/%d", item, season, episode),
		map[string]any{"watched": true})
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
}

func (e *malEnv) patch(item string, body map[string]any) {
	e.t.Helper()
	rec := e.send(http.MethodPatch, "/v1/library/items/"+item, body)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
}

func (e *malEnv) itemStatus(item string) string {
	e.t.Helper()
	return e.json(http.MethodGet, "/v1/library/items/"+item, nil)["status"].(string)
}

func lastPatch(patches []malPatch, malID string) *malPatch {
	for i := len(patches) - 1; i >= 0; i-- {
		if malID == "" || patches[i].malID == malID {
			return &patches[i]
		}
	}
	return nil
}

func TestMALConnectWithPlainPKCE(t *testing.T) {
	env := newMALEnv(t, "shh")
	location, authorize := env.connectMAL()
	assert.Equal(t, "aaru://settings?mal=connected", location)
	query := authorize.Query()
	assert.Equal(t, "myanimelist.net", authorize.Host)
	assert.Equal(t, "plain", query.Get("code_challenge_method"))

	exchange := malForm(env.mal.firstBody("/v1/oauth2/token"))
	assert.Equal(t, query.Get("code_challenge"), exchange["code_verifier"], "plain: the challenge is the verifier")
	assert.Equal(t, "shh", exchange["client_secret"])
	assert.Equal(t, "authorization_code", exchange["grant_type"])

	var sealed string
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT access_token FROM mal_connections WHERE user_id = $1`, env.user).Scan(&sealed))
	assert.NotContains(t, sealed, "at-1", "the token is never stored in clear")
	opened, err := env.cipher.Open(sealed)
	require.NoError(t, err)
	assert.Equal(t, "at-1", opened)

	status := env.malStatus()
	assert.Equal(t, true, status["connected"])
	assert.Equal(t, "ana", status["username"])
	assert.Equal(t, false, status["needsReconnect"])

	replay := env.get("/v1/connections/mal/callback?code=abc&state=" + url.QueryEscape(query.Get("state")))
	assert.Equal(t, http.StatusBadRequest, replay.Code, "a replayed callback is refused")
	assert.Contains(t, replay.Body.String(), "mal_state_invalid")
	evil := env.send(http.MethodPost, "/v1/connections/mal/connect", map[string]any{"returnTo": "https://evil.test/"})
	assert.Equal(t, http.StatusUnprocessableEntity, evil.Code, "the browser only returns to Aaru")

	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/connections/mal", nil).Code)
	assert.Equal(t, false, env.malStatus()["connected"])
}

func TestMALUnavailableWithoutClientID(t *testing.T) {
	env := newLibEnv(t)
	reply := env.send(http.MethodPost, "/v1/connections/mal/connect", map[string]any{"returnTo": "aaru://x"})
	assert.Equal(t, http.StatusServiceUnavailable, reply.Code)
	assert.Contains(t, reply.Body.String(), "mal_unavailable")
	for _, w := range env.server.Workers() {
		assert.NotEqual(t, "mal-sync", w.Name(), "no sync worker without MyAnimeList")
	}
}

func TestMALPushesPerSeason(t *testing.T) {
	env := newMALEnv(t)
	mal1, mal2 := malUniqueID(), malUniqueID()
	env.connectMAL()
	_, item := env.anime(map[int][]string{1: {mal1}, 2: {mal2}})
	for episode := 1; episode <= 3; episode++ {
		env.tick(item, 1, episode)
	}
	env.tick(item, 2, 1)
	env.patch(item, map[string]any{"rating": 7.5})

	assert.Equal(t, 2, env.push())
	sent := map[string]map[string]string{}
	for _, p := range env.mal.patches() {
		sent[p.malID] = p.fields
	}
	assert.Equal(t, map[string]string{"status": "completed", "num_watched_episodes": "3", "score": "8"}, sent[mal1])
	assert.Equal(t, map[string]string{"status": "watching", "num_watched_episodes": "1", "score": "8"}, sent[mal2])

	assert.Equal(t, 0, env.push(), "nothing changed: nothing sent")
	env.tick(item, 2, 2)
	assert.Equal(t, 1, env.push(), "only the season that moved")
	last := lastPatch(env.mal.patches(), "")
	assert.Equal(t, mal2, last.malID)
	assert.Equal(t, "2", last.fields["num_watched_episodes"])
}

func TestMALAiringSeasonOfFinishedShow(t *testing.T) {
	env := newMALEnv(t)
	mal1, mal2 := malUniqueID(), malUniqueID()
	env.connectMAL()
	tmdb := env.stubShow("Aoashi", catalog.StatusEnded, 2, 3, false)
	env.mapSeason(tmdb, mal1, 1)
	env.mapSeason(tmdb, mal2, 2)
	item := env.add("show", tmdb, "finished")
	env.push()
	completed := 0
	for _, p := range env.mal.patches() {
		if p.fields["status"] == "completed" {
			completed++
		}
	}
	assert.Equal(t, 2, completed)

	// Season 2 grows an episode still to air; the show stays finished in Aaru.
	ctx := context.Background()
	title, err := env.server.Catalog.Store.Find(ctx, core.ExternalIDs{TMDB: tmdb}, core.MediaShow)
	require.NoError(t, err)
	require.NotNil(t, title)
	airs := time.Now().Add(7 * 24 * time.Hour)
	returning := catalog.StatusReturning
	require.NoError(t, env.server.Catalog.Store.SaveEpisodes(ctx, title.ID, catalog.Episodes{
		Status: &returning, Episodes: []catalog.Episode{{Season: 2, Episode: 4, AirsAt: &airs}},
	}, time.Now()))
	env.patch(item, map[string]any{"rating": 8})
	env.push()
	last := lastPatch(env.mal.patches(), mal2)
	require.NotNil(t, last)
	assert.Equal(t, "watching", last.fields["status"], "season 2 is still airing: never completed")
	assert.Equal(t, "3", last.fields["num_watched_episodes"])
}

func TestMALOnlyLaterWritesAndNoSplitCours(t *testing.T) {
	env := newMALEnv(t)
	mal1, partA, partB := malUniqueID(), malUniqueID(), malUniqueID()
	_, item := env.anime(map[int][]string{1: {mal1}, 2: {partA, partB}})
	env.tick(item, 1, 1)
	env.connectMAL()
	assert.Equal(t, 0, env.push(), "written before connecting: not pushed")

	env.tick(item, 2, 1)
	env.push()
	sent := map[string]bool{}
	for _, p := range env.mal.patches() {
		sent[p.malID] = true
	}
	assert.Equal(t, map[string]bool{mal1: true}, sent, "season 2 has two MAL entries: Aaru cannot split it")
}

func TestMALPushesOnHold(t *testing.T) {
	env := newMALEnv(t)
	mal1 := malUniqueID()
	env.connectMAL()
	_, item := env.anime(map[int][]string{1: {mal1}})
	env.patch(item, map[string]any{"status": "on_hold", "rating": 6})
	env.push()
	last := lastPatch(env.mal.patches(), "")
	require.NotNil(t, last)
	assert.Equal(t, "on_hold", last.fields["status"])
	assert.Equal(t, "6", last.fields["score"])

	env.tick(item, 1, 1)
	assert.Equal(t, "in_progress", env.itemStatus(item), "a new tick resumes an item on hold")
	env.push()
	assert.Equal(t, "watching", lastPatch(env.mal.patches(), "").fields["status"])
}

func TestMALRevokedTokenStopsPushing(t *testing.T) {
	env := newMALEnv(t)
	mal1 := malUniqueID()
	env.connectMAL()
	_, item := env.anime(map[int][]string{1: {mal1}})
	env.mal.failPatches(401)
	env.tick(item, 1, 1)
	assert.Equal(t, 0, env.push())
	assert.Equal(t, true, env.malStatus()["needsReconnect"])

	before := len(env.mal.patches())
	env.tick(item, 1, 2)
	env.push()
	assert.Len(t, env.mal.patches(), before, "a revoked connection sends nothing")

	env.mal.failPatches(200)
	env.connectMAL()
	assert.Equal(t, false, env.malStatus()["needsReconnect"])
	env.push()
	assert.Equal(t, "2", lastPatch(env.mal.patches(), "").fields["num_watched_episodes"], "writes made while revoked go out")
}

// MARK: Reading back (SCR-010)

// malEntry is one list entry as MAL's API writes it, `updated_at` with a `+00:00` offset.
func malEntry(malID, status string, episodes, score int, updated time.Time) map[string]any {
	id, _ := strconv.Atoi(malID)
	return map[string]any{
		"node": map[string]any{"id": id, "title": "Frieren", "media_type": "tv", "num_episodes": 3},
		"list_status": map[string]any{
			"status": status, "score": score, "num_episodes_watched": episodes, "is_rewatching": false,
			"updated_at": updated.UTC().Format("2006-01-02T15:04:05") + "+00:00",
		},
	}
}

func (e *malEnv) watchedEpisodes(item string) []int {
	e.t.Helper()
	watched, err := e.server.Library.Store.WatchedSorted(context.Background(), uuid.MustParse(item))
	require.NoError(e.t, err)
	out := make([]int, len(watched))
	for i, k := range watched {
		out[i] = k.Episode
	}
	sort.Ints(out)
	return out
}

func (e *malEnv) disconnectMAL() {
	e.t.Helper()
	require.Equal(e.t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/connections/mal", nil).Code)
}

func TestMALReadsChangesSinceTheCursor(t *testing.T) {
	env := newMALEnv(t)
	mal1, older := malUniqueID(), malUniqueID()
	env.connectMAL()
	_, item := env.anime(map[int][]string{1: {mal1}})
	now := time.Now()
	env.mal.setList(
		malEntry(mal1, "watching", 2, 0, now.Add(time.Minute)),
		malEntry(older, "completed", 12, 0, now.Add(-24*time.Hour)),
	)
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodPost, "/v1/connections/mal/pull", nil).Code)
	claimed, err := env.server.MALConnect.Store.ClaimPulls(context.Background(), now, now.Add(-mal.PullInterval), time.Time{}, 1000)
	require.NoError(t, err)
	var mine *mal.PullDue
	for i := range claimed {
		if claimed[i].UserID == env.user {
			mine = &claimed[i]
		}
	}
	require.NotNil(t, mine, "an asked-for read is due")

	n, err := env.puller().Pull(context.Background(), *mine)
	require.NoError(t, err)
	assert.Equal(t, 1, n)
	assert.Equal(t, []int{1, 2}, env.watchedEpisodes(item))
	action := env.json(http.MethodGet, "/v1/actions?limit=1", nil)["items"].([]any)[0].(map[string]any)
	assert.Contains(t, action["summary"], "MyAnimeList", "the ribbon names MAL")
	assert.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+action["id"].(string)+"/undo", nil).Code)

	asked, err := env.server.MALConnect.RequestPull(context.Background(), env.user)
	require.NoError(t, err)
	assert.False(t, asked, "read under 10 min ago")
	assert.IsType(t, "", env.malStatus()["pulledAt"])

	env.mal.setList(malEntry(mal1, "watching", 3, 0, now.Add(time.Minute)))
	assert.Equal(t, 0, env.pull(now.Add(time.Minute), false), "not newer than the cursor: already read")
	env.disconnectMAL()
}

func TestMALEchoesAndBackwardMovesAreIgnored(t *testing.T) {
	env := newMALEnv(t)
	mal1, mal2 := malUniqueID(), malUniqueID()
	env.connectMAL()
	_, item := env.anime(map[int][]string{1: {mal1}})
	for episode := 1; episode <= 3; episode++ {
		env.tick(item, 1, episode)
	}
	env.push()
	assert.Equal(t, "completed", lastPatch(env.mal.patches(), "").fields["status"])
	actions := env.actionCount()

	now := time.Now()
	env.mal.setList(malEntry(mal1, "completed", 3, 0, now.Add(time.Minute)))
	assert.Equal(t, 0, env.pull(now, false), "Aaru's own push")
	assert.Equal(t, actions, env.actionCount())

	env.mal.setList(malEntry(mal1, "watching", 1, 0, now.Add(2*time.Minute)))
	assert.Equal(t, 0, env.pull(now.Add(time.Minute), false))
	assert.Len(t, env.watchedEpisodes(item), 3, "MAL's fewer ticks untick nothing")

	_, planned := env.anime(map[int][]string{1: {mal2}})
	env.patch(planned, map[string]any{"status": "wishlist"})
	env.mal.setList(malEntry(mal2, "completed", 3, 0, now.Add(3*time.Minute)))
	env.pull(now.Add(2*time.Minute), false)
	assert.Equal(t, "wishlist", env.itemStatus(planned), "a status the user set by hand stays")
	env.disconnectMAL()
}

func TestMALOnHoldReadBack(t *testing.T) {
	env := newMALEnv(t)
	mal1 := malUniqueID()
	env.connectMAL()
	_, item := env.anime(map[int][]string{1: {mal1}}, "wishlist")
	env.tick(item, 1, 1)
	assert.Equal(t, "in_progress", env.itemStatus(item), "a tick, not a status set by hand")

	now := time.Now()
	env.mal.setList(malEntry(mal1, "on_hold", 1, 0, now.Add(time.Minute)))
	assert.Equal(t, 1, env.pull(now, false))
	assert.Equal(t, "on_hold", env.itemStatus(item))

	env.mal.setList(malEntry(mal1, "watching", 1, 0, now.Add(2*time.Minute)))
	assert.Equal(t, 1, env.pull(now.Add(time.Minute), false))
	assert.Equal(t, "in_progress", env.itemStatus(item))
	env.disconnectMAL()
}

func TestMALRemovalsAreListedNotApplied(t *testing.T) {
	env := newMALEnv(t)
	mal1, mal2 := malUniqueID(), malUniqueID()
	env.connectMAL()
	_, item := env.anime(map[int][]string{1: {mal1}})
	store := env.server.MALConnect.Store
	for id, name := range map[string]string{mal1: "Frieren", mal2: "Dungeon Meshi"} {
		title := name
		require.NoError(t, store.SaveEntryState(context.Background(),
			mal.EntryState{MalID: id, Status: mal.Watching, Episodes: 1}, &title, env.user))
	}
	now := time.Now()
	env.mal.setList(malEntry(mal1, "watching", 1, 0, now.Add(-time.Minute)))
	env.pull(now, true)
	removed := env.malStatus()["removed"].([]any)
	require.Len(t, removed, 1)
	assert.Equal(t, "Dungeon Meshi", removed[0].(map[string]any)["title"])
	assert.Equal(t, "in_progress", env.itemStatus(item))

	env.mal.setList(
		malEntry(mal2, "watching", 1, 0, now.Add(-30*time.Second)),
		malEntry(mal1, "watching", 1, 0, now.Add(-time.Minute)),
	)
	env.pull(now, true)
	assert.Empty(t, env.malStatus()["removed"], "back on MAL: no longer listed")
	env.disconnectMAL()
}

func TestMALRevokedWhileReading(t *testing.T) {
	env := newMALEnv(t)
	env.connectMAL()
	env.mal.failList(401)
	assert.Equal(t, 0, env.pull(time.Now(), false))
	assert.Equal(t, true, env.malStatus()["needsReconnect"])
}
