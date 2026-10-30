package httpapi

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/scrobble"
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// NowPlayingTests.swift (+LateToken, +Plays): SCR-008, SCR-009, against a fake APNs. No real key, no network.

type sentLiveActivity struct {
	push  push.LiveActivityPush
	token push.LiveActivityToken
}

// fakeLiveActivity records what would have gone to Apple; some tokens are "dead".
type fakeLiveActivity struct {
	mu   sync.Mutex
	sent []sentLiveActivity
	dead map[string]bool
}

func (f *fakeLiveActivity) SendLiveActivity(_ context.Context, p push.LiveActivityPush, t push.LiveActivityToken) (push.Outcome, error) {
	if f.dead[t.Token] {
		return push.DeadToken, nil
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.sent = append(f.sent, sentLiveActivity{p, t})
	return push.Sent, nil
}

func (f *fakeLiveActivity) pushes() []sentLiveActivity {
	f.mu.Lock()
	defer f.mu.Unlock()
	return slices.Clone(f.sent)
}

func (f *fakeLiveActivity) last(t *testing.T) sentLiveActivity {
	t.Helper()
	all := f.pushes()
	require.NotEmpty(t, all)
	return all[len(all)-1]
}

func content(p push.LiveActivityPush) core.NowPlayingActivityState {
	return p.Content.(core.NowPlayingActivityState)
}

// liveToken is a random APNs-shaped token (PushTests.token()).
func liveToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

type nowPlayingEnv struct {
	*scrobbleEnv
	apns   *fakeLiveActivity
	caller auth.AgentCaller
}

func newNowPlayingEnv(t *testing.T, dead ...string) *nowPlayingEnv {
	t.Helper()
	env := newScrobbleEnv(t)
	apns := &fakeLiveActivity{dead: map[string]bool{}}
	for _, d := range dead {
		apns.dead[d] = true
	}
	s := env.server.Scrobble
	s.Notifier = &scrobble.Notifier{Store: s.Store, Titles: env.server.Catalog.Store, Sender: apns, Log: env.server.Log}
	return &nowPlayingEnv{scrobbleEnv: env, apns: apns, caller: env.stremioCaller()}
}

func numbered(tmdb string, number int, action scrobble.Action, position, duration int64) scrobble.Report {
	k := key(1, number)
	return scrobble.Report{
		Source: scrobble.SourceStremio, ExternalRef: tmdb + ":1:" + itoa(number), Type: core.MediaShow,
		IDs: core.ExternalIDs{TMDB: tmdb}, Episode: &k, Action: action, PositionMs: position, DurationMs: duration,
	}
}

func (e *nowPlayingEnv) watchedOf(tmdb string) []core.EpisodeKey {
	e.t.Helper()
	item, _, ok := e.itemOf(tmdb, core.MediaShow)
	require.True(e.t, ok)
	return e.watchedKeys(item)
}

func (e *nowPlayingEnv) registerToken(kind, token string) int {
	e.t.Helper()
	return e.send(http.MethodPut, "/v1/devices/live-activity", map[string]any{
		"token": token, "kind": kind, "environment": "production", "bundleId": "com.fernandocorreia.aaru.beta",
	}).Code
}

func (e *nowPlayingEnv) sweep(at time.Time) {
	e.t.Helper()
	w := &scrobble.SweepWorker{Notifier: e.server.Scrobble.Notifier, Now: func() time.Time { return at }}
	require.NoError(e.t, w.Sweep(context.Background()))
}

func openSession(state scrobble.State, position, duration int64, runtime *int, reportedAgo time.Duration) scrobble.OpenSession {
	return scrobble.OpenSession{
		ID: uuid.New(), Source: scrobble.SourceStremio, ExternalRef: "tt1:1:1", TitleID: uuid.New(),
		RuntimeMinutes: runtime, State: state, PositionMs: position, DurationMs: duration,
		UpdatedAt: time.Unix(1_000_000, 0).Add(-reportedAgo),
	}
}

func TestNowPlayingLiveness(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	// 20 of 50 minutes in, reported 25 minutes ago: 5 minutes left.
	assert.True(t, scrobble.IsLive(openSession(scrobble.Playing, 1_200_000, 3_000_000, nil, 25*time.Minute), now))
	// Reported 41 minutes ago: past its end and the 10-minute grace.
	assert.False(t, scrobble.IsLive(openSession(scrobble.Playing, 1_200_000, 3_000_000, nil, 41*time.Minute), now))
	assert.True(t, scrobble.IsLive(openSession(scrobble.Paused, 0, 0, nil, 29*time.Minute), now))
	assert.False(t, scrobble.IsLive(openSession(scrobble.Paused, 0, 0, nil, 31*time.Minute), now))
	assert.True(t, scrobble.IsLive(openSession(scrobble.Playing, 0, 0, nil, 2*time.Hour), now))
	assert.False(t, scrobble.IsLive(openSession(scrobble.Playing, 0, 0, nil, 4*time.Hour), now))
	// No player duration: the 45-minute runtime stands in.
	runtime := 45
	assert.False(t, scrobble.IsLive(openSession(scrobble.Playing, 0, 0, &runtime, 56*time.Minute), now))
}

func TestNowPlayingEachStopPast80TicksItsOwnEpisodeOnce(t *testing.T) {
	env := newNowPlayingEnv(t)
	tmdb := env.stubShow("Cyberpunk: Edgerunners", catalog.StatusEnded, 2, 3, false)
	env.add("show", tmdb, "in_progress")
	before := env.actionCount()
	env.report(numbered(tmdb, 2, scrobble.ActionStart, 0, 3_000_000), env.caller)
	assert.Equal(t, scrobble.Watched, env.report(numbered(tmdb, 2, scrobble.ActionStop, 2_980_000, 3_000_000), env.caller))
	env.report(numbered(tmdb, 3, scrobble.ActionStart, 0, 3_000_000), env.caller)
	assert.Equal(t, scrobble.Watched, env.report(numbered(tmdb, 3, scrobble.ActionStop, 2_980_000, 3_000_000), env.caller))
	assert.Equal(t, []core.EpisodeKey{key(1, 2), key(1, 3)}, env.watchedOf(tmdb))
	assert.Equal(t, before+2, env.actionCount())
	assert.Equal(t, scrobble.StoppedWithoutChange, env.report(numbered(tmdb, 3, scrobble.ActionStop, 2_980_000, 3_000_000), env.caller),
		"a repeat stop is still a no-op")
}

func TestNowPlayingNextEpisodeWithoutAStopClosesTheLastTickingOnlyPast80(t *testing.T) {
	env := newNowPlayingEnv(t)
	tmdb := env.stubShow("Andor", catalog.StatusEnded, 2, 3, false)
	env.add("show", tmdb, "in_progress")
	env.report(numbered(tmdb, 1, scrobble.ActionStart, 0, 3_000_000), env.caller)
	env.report(numbered(tmdb, 1, scrobble.ActionPause, 1_200_000, 3_000_000), env.caller)
	env.report(numbered(tmdb, 2, scrobble.ActionStart, 0, 3_000_000), env.caller)
	assert.Empty(t, env.watchedOf(tmdb), "40% reported is not watched")

	env.report(numbered(tmdb, 2, scrobble.ActionPause, 2_700_000, 3_000_000), env.caller)
	env.report(numbered(tmdb, 3, scrobble.ActionStart, 0, 3_000_000), env.caller)
	assert.Equal(t, []core.EpisodeKey{key(1, 2)}, env.watchedOf(tmdb))

	source := scrobble.SourceStremio
	open, err := env.server.Scrobble.Store.OpenSessions(context.Background(), env.user, &source, 10)
	require.NoError(t, err)
	var refs []string
	for _, s := range open {
		refs = append(refs, s.ExternalRef)
	}
	assert.Equal(t, []string{tmdb + ":1:3"}, refs, "only the new episode stays open")
}

func TestNowPlayingEndpointShowsTheOpenEpisodeAndNothingOnceItStops(t *testing.T) {
	env := newNowPlayingEnv(t)
	tmdb := env.stubShow("Slow Horses", catalog.StatusReturning, 2, 3, false)
	itemID := env.add("show", tmdb, "in_progress")
	assert.NotContains(t, env.json(http.MethodGet, "/v1/me/now-playing", nil), "nowPlaying")

	env.report(numbered(tmdb, 2, scrobble.ActionStart, 600_000, 3_000_000), env.caller)
	reply := env.json(http.MethodGet, "/v1/me/now-playing", nil)
	playing := reply["nowPlaying"].(map[string]any)
	assert.Equal(t, "playing", playing["state"])
	assert.Equal(t, "stremio", playing["source"])
	assert.InDelta(t, 600_000, playing["positionMs"], 0)
	assert.InDelta(t, 3_000_000, playing["durationMs"], 0)
	assert.Equal(t, strings.ToLower(itemID), strings.ToLower(playing["libraryItemId"].(string)))
	watchEvent := playing["watchEventId"].(string)
	assert.Equal(t, strings.ToLower(watchEvent), watchEvent, "lowercase, as Swift sent it")
	assert.Equal(t, "S1E2", playing["episodeName"])
	assert.InDelta(t, 2, playing["episode"].(map[string]any)["number"], 0)
	assert.Equal(t, "Slow Horses", playing["title"].(map[string]any)["title"])

	env.report(numbered(tmdb, 2, scrobble.ActionStop, 2_900_000, 3_000_000), env.caller)
	assert.NotContains(t, env.json(http.MethodGet, "/v1/me/now-playing", nil), "nowPlaying")
}

func TestNowPlayingLiveActivityStartUpdateWatchedLingerAndSweepEnd(t *testing.T) {
	dead := "dead" + strings.Repeat("0", 60)
	env := newNowPlayingEnv(t, dead)
	tmdb := env.stubShow("Pluribus", catalog.StatusReturning, 2, 3, false)
	env.add("show", tmdb, "in_progress")
	start := liveToken()
	assert.Equal(t, http.StatusNoContent, env.registerToken("start", start))
	assert.Equal(t, http.StatusNoContent, env.registerToken("start", dead))

	env.report(numbered(tmdb, 2, scrobble.ActionStart, 60000, 3_000_000), env.caller)
	started := env.apns.pushes()
	require.Len(t, started, 1)
	p := started[0]
	assert.Equal(t, start, p.token.Token)
	assert.Equal(t, push.LiveActivityStart, p.push.Event)
	assert.Equal(t, "Now playing", p.push.AlertTitle)
	assert.Equal(t, "Pluribus · S1 · E2 · S1E2", p.push.AlertBody)
	assert.False(t, p.push.Considerate)
	items := content(p.push).Items
	require.Len(t, items, 1)
	assert.Equal(t, core.NowPlayingKind("episode"), items[0].Kind)
	assert.Equal(t, "Stremio", *items[0].Service)
	require.NotNil(t, items[0].EndsAt)
	assert.Equal(t, 3000*time.Second, items[0].EndsAt.Sub(items[0].StartedAt.Time))
	tokens, err := env.server.Scrobble.Store.LiveActivityTokens(context.Background(), env.user, push.LiveActivityTokenStart)
	require.NoError(t, err)
	require.Len(t, tokens, 1, "the dead token is forgotten")
	assert.Equal(t, start, tokens[0].Token)

	// The player reporting on, with nothing new to show, pushes nothing.
	env.report(numbered(tmdb, 2, scrobble.ActionStart, 90000, 3_000_000), env.caller)
	assert.Len(t, env.apns.pushes(), 1)

	running := liveToken()
	assert.Equal(t, http.StatusNoContent, env.registerToken("update", running))
	// The route catches the new token up at once. Swift's test saw no such push only because its route
	// used the harness's scrobble service, which had no notifier; the handler does the same as here.
	caught := env.apns.last(t)
	assert.Equal(t, push.LiveActivityUpdate, caught.push.Event)
	assert.Equal(t, running, caught.token.Token)
	assert.Len(t, env.apns.pushes(), 2)
	env.report(numbered(tmdb, 2, scrobble.ActionPause, 900_000, 3_000_000), env.caller)
	paused := env.apns.last(t)
	assert.Equal(t, push.LiveActivityUpdate, paused.push.Event)
	assert.True(t, paused.push.Considerate)
	assert.NotNil(t, content(paused.push).Items[0].PausedAt)
	assert.Equal(t, running, paused.token.Token)

	env.report(numbered(tmdb, 2, scrobble.ActionStop, 2_950_000, 3_000_000), env.caller)
	watched := env.apns.last(t)
	assert.Equal(t, push.LiveActivityUpdate, watched.push.Event)
	var flags []bool
	for _, it := range content(watched.push).Items {
		flags = append(flags, it.Watched)
	}
	assert.Equal(t, []bool{true}, flags, "the ticked row lingers as Watched")
	assert.Len(t, env.apns.pushes(), 4)

	env.sweep(time.Now().Add(scrobble.WatchedLinger + time.Second))
	assert.Equal(t, push.LiveActivityEnd, env.apns.last(t).push.Event)
	assert.Len(t, env.apns.pushes(), 5)
	updates, err := env.server.Scrobble.Store.LiveActivityTokens(context.Background(), env.user, push.LiveActivityTokenUpdate)
	require.NoError(t, err)
	assert.Empty(t, updates)
}

func TestNowPlayingLiveActivityTokenRegistrationRefusesBadInput(t *testing.T) {
	env := newNowPlayingEnv(t)
	assert.Equal(t, http.StatusNoContent, env.registerToken("update", liveToken()))
	assert.Equal(t, http.StatusUnprocessableEntity, env.registerToken("start", "not-hex"))
	foreign := env.send(http.MethodPut, "/v1/devices/live-activity", map[string]any{
		"token": liveToken(), "kind": "start", "environment": "sandbox", "bundleId": "com.example.other",
	})
	assert.Equal(t, http.StatusUnprocessableEntity, foreign.Code)
}

func TestNowPlayingLateTokenHearsThePauseThenTheStopItMissed(t *testing.T) {
	env := newNowPlayingEnv(t)
	tmdb := env.stubShow("Severance", catalog.StatusReturning, 2, 3, false)
	env.add("show", tmdb, "in_progress")
	assert.Equal(t, http.StatusNoContent, env.registerToken("start", liveToken()))
	env.report(numbered(tmdb, 1, scrobble.ActionStart, 60000, 3_000_000), env.caller)
	require.NotEmpty(t, env.apns.pushes())
	assert.Equal(t, push.LiveActivityStart, env.apns.pushes()[0].push.Event)
	env.report(numbered(tmdb, 1, scrobble.ActionPause, 600_000, 3_000_000), env.caller)
	assert.Len(t, env.apns.pushes(), 1, "no activity token yet, so the pause has nowhere to go")

	notifier := env.server.Scrobble.Notifier
	late := push.LiveActivityToken{Token: liveToken(), Kind: push.LiveActivityTokenUpdate, Environment: push.Production, Topic: "com.fernandocorreia.aaru.beta"}
	notifier.CaughtUp(context.Background(), late, env.user, time.Now())
	caught := env.apns.last(t)
	assert.Equal(t, push.LiveActivityUpdate, caught.push.Event)
	assert.NotNil(t, content(caught.push).Items[0].PausedAt)
	assert.Equal(t, late.Token, caught.token.Token)

	// Stopped short of 80%: nothing is left, so a token turning up after hears the end.
	env.report(numbered(tmdb, 1, scrobble.ActionStop, 700_000, 3_000_000), env.caller)
	notifier.CaughtUp(context.Background(), late, env.user, time.Now())
	assert.Equal(t, push.LiveActivityEnd, env.apns.last(t).push.Event)
	assert.Len(t, env.apns.pushes(), 3)
}
