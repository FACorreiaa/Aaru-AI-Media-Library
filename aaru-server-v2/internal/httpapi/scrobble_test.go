package httpapi

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/scrobble"
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ScrobbleTests.swift (SCR-001) and ScrobbleRouteTests.swift (SCR-001, SCR-007).

func stremioEpisode(tmdb string, action scrobble.Action, position, duration int64) scrobble.Report {
	k := key(1, 2)
	return scrobble.Report{
		Source: scrobble.SourceStremio, ExternalRef: tmdb + ":1:2", Type: core.MediaShow,
		IDs: core.ExternalIDs{TMDB: tmdb}, Episode: &k, Action: action, PositionMs: position, DurationMs: duration,
	}
}

func (e *scrobbleEnv) stremioCaller() auth.AgentCaller {
	_, secret := e.connect("stremio")
	return e.caller(secret, auth.GroupStremio)
}

func (e *scrobbleEnv) report(r scrobble.Report, caller auth.AgentCaller) scrobble.Outcome {
	e.t.Helper()
	out, err := e.server.Scrobble.Report(context.Background(), r, caller)
	require.NoError(e.t, err)
	return out
}

func TestScrobbleWatchedEpisodeTicksOnceAndARepeatStopIsANoOp(t *testing.T) {
	env := newScrobbleEnv(t)
	caller := env.stremioCaller()
	tmdb := env.stubShow("Andor", catalog.StatusEnded, 2, 3, false)
	env.add("show", tmdb, "in_progress")
	before := env.actionCount()

	assert.Equal(t, scrobble.Recorded, env.report(stremioEpisode(tmdb, scrobble.ActionStart, 0, 0), caller))
	assert.Equal(t, scrobble.Recorded, env.report(stremioEpisode(tmdb, scrobble.ActionPause, 900_000, 3_000_000), caller))
	assert.Equal(t, before, env.actionCount(), "start and pause never change progress")
	assert.Equal(t, scrobble.Watched, env.report(stremioEpisode(tmdb, scrobble.ActionStop, 2_550_000, 3_000_000), caller))
	assert.Equal(t, before+1, env.actionCount())
	item, _, ok := env.itemOf(tmdb, core.MediaShow)
	require.True(t, ok)
	assert.Equal(t, []core.EpisodeKey{key(1, 2)}, env.watchedKeys(item))

	assert.Equal(t, scrobble.StoppedWithoutChange, env.report(stremioEpisode(tmdb, scrobble.ActionStop, 2_550_000, 3_000_000), caller))
	assert.Equal(t, before+1, env.actionCount(), "a duplicate stop writes nothing")
}

func TestScrobbleStopShortOrWithUnknownDurationTicksNothing(t *testing.T) {
	env := newScrobbleEnv(t)
	caller := env.stremioCaller()
	tmdb := env.stubShow("Pluribus", catalog.StatusEnded, 2, 3, false)
	env.add("show", tmdb, "in_progress")
	before := env.actionCount()
	assert.Equal(t, scrobble.StoppedWithoutChange, env.report(stremioEpisode(tmdb, scrobble.ActionStop, 1_500_000, 3_000_000), caller))
	unknown := stremioEpisode(tmdb, scrobble.ActionStop, 2_900_000, 0)
	unknown.ExternalRef = tmdb + ":1:3"
	assert.Equal(t, scrobble.StoppedWithoutChange, env.report(unknown, caller))
	assert.Equal(t, before, env.actionCount())
}

func TestScrobbleDurationLearnedAtStartCountsWhenStopReportsZero(t *testing.T) {
	env := newScrobbleEnv(t)
	caller := env.stremioCaller()
	tmdb := env.stubShow("Shogun", catalog.StatusEnded, 2, 3, false)
	env.add("show", tmdb, "in_progress")
	env.report(stremioEpisode(tmdb, scrobble.ActionStart, 0, 3_000_000), caller)
	assert.Equal(t, scrobble.Watched, env.report(stremioEpisode(tmdb, scrobble.ActionStop, 2_700_000, 0), caller))
}

func TestScrobbleAbsentShowIsAddedInProgressAndJournaledAsTheAgent(t *testing.T) {
	env := newScrobbleEnv(t)
	caller := env.stremioCaller()
	tmdb := env.stubShow("Slow Horses", catalog.StatusReturning, 2, 3, false)
	assert.Equal(t, scrobble.Watched, env.report(stremioEpisode(tmdb, scrobble.ActionStop, 2_900_000, 3_000_000), caller))
	_, status, ok := env.itemOf(tmdb, core.MediaShow)
	require.True(t, ok)
	assert.Equal(t, "in_progress", status)
	actions := env.actions(2)
	for _, a := range actions {
		assert.Equal(t, "external_agent", a["actor"])
	}
	assert.Equal(t, "Stremio: marked S01E02 of Slow Horses watched", actions[0]["summary"])
}

func TestScrobbleMovieIsFinishedAndAnUnknownIDIsUnmatched(t *testing.T) {
	env := newScrobbleEnv(t)
	caller := env.stremioCaller()
	tmdb := env.stubMovie("Arrival")
	movie := scrobble.Report{
		Source: scrobble.SourceStremio, ExternalRef: "tt-" + tmdb, Type: core.MediaMovie,
		IDs: core.ExternalIDs{TMDB: tmdb}, Action: scrobble.ActionStop, PositionMs: 6_500_000, DurationMs: 7_000_000,
	}
	assert.Equal(t, scrobble.Watched, env.report(movie, caller))
	_, status, ok := env.itemOf(tmdb, core.MediaMovie)
	require.True(t, ok)
	assert.Equal(t, "finished", status)

	before := env.actionCount()
	unknown := scrobble.Report{
		Source: scrobble.SourceStremio, ExternalRef: "tt0000000", Type: core.MediaMovie,
		IDs: core.ExternalIDs{IMDB: "tt0000000"}, Action: scrobble.ActionStop, PositionMs: 100, DurationMs: 100,
	}
	assert.Equal(t, scrobble.Unmatched, env.report(unknown, caller))
	assert.Equal(t, before, env.actionCount())
}

// Routes.

func (e *scrobbleEnv) scrobble(action string, body any, token string) (int, map[string]any) {
	e.t.Helper()
	rec := e.do(http.MethodPost, "/v1/scrobble/"+action, token, body)
	var out map[string]any
	if rec.Body.Len() > 0 {
		out = decode[map[string]any](e.t, rec)
	}
	return rec.Code, out
}

// searchableShow is a show the fake TMDB finds by its name, with episodes named `S1E1`….
func (e *scrobbleEnv) searchableShow(name string) string {
	tmdb := e.stubShow(name, catalog.StatusReturning, 2, 3, false)
	year := 2020
	e.search.stubSearch(name, []catalog.Hit{{Type: core.MediaShow, Title: name, Year: &year, IDs: core.ExternalIDs{TMDB: tmdb}}})
	return tmdb
}

func netflixEpisode(show, ref string, progress float64, number *int) map[string]any {
	episode := map[string]any{"season": 1, "title": "S1E2"}
	if number != nil {
		episode["number"] = *number
	}
	return map[string]any{
		"source": "netflix", "ref": ref, "show": map[string]any{"title": show}, "episode": episode,
		"progress": progress, "durationMs": 3_000_000,
	}
}

func two() *int { n := 2; return &n }

func TestScrobbleRouteWatchedEpisodeIsJournaledAsTheExtension(t *testing.T) {
	env := newScrobbleEnv(t)
	name := env.fake.uniqueID("Severance")
	tmdb := env.searchableShow(name)
	_, token := env.connect("browser")
	before := env.actionCount()
	ref := env.fake.uniqueID("81000")

	code, answer := env.scrobble("start", netflixEpisode(name, ref, 0, two()), token)
	require.Equal(t, http.StatusOK, code, answer)
	assert.Equal(t, "recorded", answer["outcome"])
	assert.Equal(t, name, answer["title"].(map[string]any)["name"])
	env.scrobble("pause", netflixEpisode(name, ref, 30, two()), token)
	assert.Equal(t, before, env.actionCount(), "start and pause never change progress")
	_, answer = env.scrobble("stop", netflixEpisode(name, ref, 85, two()), token)
	assert.Equal(t, "watched", answer["outcome"])
	assert.Equal(t, before+2, env.actionCount(), "added to the library, then ticked")
	item, _, ok := env.itemOf(tmdb, core.MediaShow)
	require.True(t, ok)
	assert.Equal(t, []core.EpisodeKey{key(1, 2)}, env.watchedKeys(item))
	assert.Equal(t, "Browser extension: marked S01E02 of "+name+" watched", env.actions(1)[0]["summary"])

	_, answer = env.scrobble("stop", netflixEpisode(name, ref, 85, two()), token)
	assert.Equal(t, "stopped", answer["outcome"])
	assert.Equal(t, before+2, env.actionCount(), "a duplicate stop writes nothing")
}

func TestScrobbleRouteMatchesAnEpisodeByNameAndLeavesAnAmbiguousFilmUnmatched(t *testing.T) {
	env := newScrobbleEnv(t)
	name := env.fake.uniqueID("Pluribus")
	tmdb := env.searchableShow(name)
	_, token := env.connect("browser")
	_, answer := env.scrobble("stop", netflixEpisode(name, env.fake.uniqueID("ref"), 95, nil), token)
	assert.Equal(t, "watched", answer["outcome"])
	item, _, ok := env.itemOf(tmdb, core.MediaShow)
	require.True(t, ok)
	assert.Equal(t, []core.EpisodeKey{key(1, 2)}, env.watchedKeys(item))

	film := env.fake.uniqueID("Solaris")
	var hits []catalog.Hit
	for _, year := range []int{1972, 2002} {
		y := year
		hits = append(hits, catalog.Hit{Type: core.MediaMovie, Title: film, Year: &y, IDs: core.ExternalIDs{TMDB: env.fake.uniqueID("tmdb")}})
	}
	env.search.stubSearch(film, hits)
	before := env.actionCount()
	_, answer = env.scrobble("stop", map[string]any{
		"source": "prime_video", "ref": env.fake.uniqueID("ref"), "movie": map[string]any{"title": film}, "progress": 99,
	}, token)
	assert.Equal(t, "unmatched", answer["outcome"])
	assert.NotContains(t, answer, "title")
	assert.Equal(t, before, env.actionCount())
}

func TestScrobbleRouteOnlyALiveBrowserTokenGetsIn(t *testing.T) {
	env := newScrobbleEnv(t)
	body := netflixEpisode("Anything", "1", 10, two())
	browserID, browser := env.connect("browser")
	_, mcp := env.connect("claude_code")
	_, stremio := env.connect("stremio")
	for _, token := range []string{env.bearer, mcp, stremio, "aaru_scr_nope"} {
		code, _ := env.scrobble("start", body, token)
		assert.Equal(t, http.StatusUnauthorized, code, token)
	}
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/agent/tokens/"+browserID, nil).Code)
	code, _ := env.scrobble("start", body, browser)
	assert.Equal(t, http.StatusUnauthorized, code)
}

func TestScrobbleRouteBrowserTokenOnlyScrobblesAndIsListedOnItsOwnSurface(t *testing.T) {
	env := newScrobbleEnv(t)
	_, secret := env.connect("browser")
	assert.True(t, strings.HasPrefix(secret, auth.ScrobblePrefix))
	listed := env.json(http.MethodGet, "/v1/agent/tokens?for=scrobble", nil)["items"].([]any)
	require.Len(t, listed, 1)
	first := listed[0].(map[string]any)
	assert.Equal(t, "browser", first["kind"])
	assert.Equal(t, []any{"scrobble:write"}, first["scopes"])
	assert.Empty(t, env.json(http.MethodGet, "/v1/agent/tokens", nil)["items"])
	// Swift also checked `POST /v1/mcp` refuses it (401); MCP is ported in another area, so that
	// assertion belongs with the MCP tests once the route exists here.
}

func TestScrobbleRouteRefusesABodyThatIsNotAScrobble(t *testing.T) {
	env := newScrobbleEnv(t)
	_, token := env.connect("browser")
	bad := []map[string]any{
		{"source": "stremio", "ref": "1", "movie": map[string]any{"title": "Roma"}, "progress": 10},
		{"source": "netflix", "ref": "1", "show": map[string]any{"title": "Dark"}, "progress": 10},
		{"source": "netflix", "ref": "1", "movie": map[string]any{"title": "Roma"}, "progress": 140},
		{"source": "netflix", "ref": "", "movie": map[string]any{"title": "Roma"}, "progress": 10},
		{"source": "netflix", "ref": "1", "movie": map[string]any{}, "progress": 10},
		{"source": "netflix", "ref": "1", "progress": 10},
	}
	for _, body := range bad {
		code, reply := env.scrobble("start", body, token)
		assert.Equal(t, http.StatusUnprocessableEntity, code, body)
		assert.Equal(t, "validation_failed", reply["code"], body)
	}
}
