package httpapi

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/library"
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GamificationTests.swift and LeaderboardTests.swift through the routes: the library, social and
// scrobble writes that earn points, as a client makes them. The rules themselves are unit-tested in
// internal/gamification.

// newEvaluatedLibEnvG6 is the library harness with its user signed up as sign-up does it: evaluated,
// so a first award is live rather than the one-time backfill.
func newEvaluatedLibEnvG6(t *testing.T) *libEnv {
	t.Helper()
	e := newLibEnv(t)
	e.evaluated(e.user)
	return e
}

func (e *libEnv) pointsG6(bearer ...string) int {
	e.t.Helper()
	rec := e.send(http.MethodGet, "/v1/me/progress", nil, bearer...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return int(decode[map[string]any](e.t, rec)["total"].(float64))
}

func (e *libEnv) undoLastG6() {
	e.t.Helper()
	id := e.actions(1)[0]["id"].(string)
	rec := e.send(http.MethodPost, "/v1/actions/"+id+"/undo", nil)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
}

func (e *libEnv) unseenBadgesG6() (origin string, badges, ids []string) {
	e.t.Helper()
	unseen := e.json(http.MethodGet, "/v1/me/progress", nil)["unseen"].(map[string]any)
	if o, ok := unseen["origin"].(string); ok {
		origin = o
	}
	items, _ := unseen["items"].([]any)
	for _, it := range items {
		award := it.(map[string]any)
		badges = append(badges, award["badge"].(string))
		ids = append(ids, award["id"].(string))
	}
	return origin, badges, ids
}

func (e *libEnv) tickG6(item string, season, episode int, watched bool) {
	e.t.Helper()
	rec := e.send(http.MethodPut, "/v1/library/items/"+item+"/episodes/"+itoa(season)+"/"+itoa(episode), map[string]any{"watched": watched})
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
}

func (e *libEnv) earnedBadgeG6(badge string) bool {
	e.t.Helper()
	var n int
	require.NoError(e.t, e.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM user_badges WHERE user_id = $1 AND badge = $2`, e.user, badge).Scan(&n))
	return n > 0
}

// tickUndoRedo
func TestRouteTickEarnsOnceUntickTakesBackUndoRedoNetsOne(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	id := e.add("show", e.stubShow("Andor", catalog.StatusReturning, 1, 3, false))
	e.tickG6(id, 1, 1, true)
	assert.Equal(t, 10, e.pointsG6())
	e.tickG6(id, 1, 1, true)
	assert.Equal(t, 10, e.pointsG6(), "ticking again earns nothing")

	e.tickG6(id, 1, 1, false)
	assert.Equal(t, 0, e.pointsG6())
	e.tickG6(id, 1, 1, true)
	assert.Equal(t, 10, e.pointsG6())

	e.undoLastG6()
	assert.Equal(t, 0, e.pointsG6())
	e.undoLastG6()
	assert.Equal(t, 10, e.pointsG6(), "undo then redo nets one award")

	rebuilt, err := e.server.Gamification.RebuildTotal(context.Background(), e.user)
	require.NoError(t, err)
	assert.Equal(t, e.pointsG6(), rebuilt)
}

// seasonBonus
func TestRouteFullSeasonEarnsItsBonusAndUndoTakesAllBack(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	id := e.add("show", e.stubShow("Severance", catalog.StatusEnded, 1, 3, false))
	rec := e.send(http.MethodPost, "/v1/library/items/"+id+"/seasons/1/watched", nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.Equal(t, 3*10+30, e.pointsG6())
	e.undoLastG6()
	assert.Equal(t, 0, e.pointsG6())
}

// dailyCap
func TestRouteDailyCapsHold(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	id := e.add("show", e.stubShow("The Wire", catalog.StatusEnded, 1, 35, false))
	rec := e.send(http.MethodPost, "/v1/library/items/"+id+"/seasons/1/watched", nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.Equal(t, 300+30, e.pointsG6(), "episodes stop at 300 a day; the season bonus has its own cap")
}

// scrobbleOnce
func TestScrobbleMarkWatchedAwardsOnceWithTheBonus(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	_, secret := e.connectAgent("stremio")
	tmdb := e.stubShow("Andor", catalog.StatusEnded, 1, 3, false)
	e.add("show", tmdb, "in_progress")
	title := core.Title{ID: *e.titleID(tmdb, core.MediaShow), Type: core.MediaShow}
	caller := e.caller(secret, auth.GroupStremio)
	wrote, err := e.server.Scrobble.MarkWatched(context.Background(), title, []core.EpisodeKey{key(1, 2)}, caller)
	require.NoError(t, err)
	assert.True(t, wrote)
	assert.Equal(t, 15, e.pointsG6())
	_, err = e.server.Scrobble.MarkWatched(context.Background(), title, []core.EpisodeKey{key(1, 2)}, caller)
	require.NoError(t, err)
	assert.Equal(t, 15, e.pointsG6(), "a replayed scrobble earns nothing twice")
}

// importsEarnNothing
func TestLibraryImportAndPlanWritesEarnNothingAndNoStreakDay(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	item := uuid.MustParse(e.add("show", e.stubShow("Lost", catalog.StatusEnded, 1, 3, false)))
	for _, kind := range []string{"import", "plan"} {
		_, err := e.server.Library.Store.Apply(context.Background(),
			library.SetEpisodes(item, []core.EpisodeKey{key(1, 1), key(1, 2)}, nil), e.user, library.UserCaller, kind, kind)
		require.NoError(t, err)
	}
	assert.Equal(t, 0, e.pointsG6())
	days, err := e.server.Gamification.StreakDays(context.Background(), e.user)
	require.NoError(t, err)
	assert.Empty(t, days)
}

// friendPoints
func TestRouteFriendshipEarnsBothUnfriendTakesBackRefriendEarnsNothing(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	ana := e.friendsByInvite()
	assert.Equal(t, 20, e.pointsG6())
	assert.Equal(t, 20, e.pointsG6(ana.token))
	rec := e.send(http.MethodDelete, "/v1/social/friends/"+up(ana.id), nil)
	require.Equal(t, http.StatusNoContent, rec.Code, rec.Body.String())
	assert.Equal(t, 0, e.pointsG6())
	assert.Equal(t, 0, e.pointsG6(ana.token))

	code := e.json(http.MethodPost, "/v1/social/invites", map[string]any{})["code"].(string)
	rec = e.send(http.MethodPost, "/v1/social/invites/"+code+"/redeem", map[string]any{"addTitle": false}, ana.token)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.Equal(t, 0, e.pointsG6(), "the pair's points were spent")
}

// streakDayZone
func TestRouteStreakDayIsDatedInXTimezoneAndTheZoneIsKept(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	id := e.add("show", e.stubShow("Shogun", catalog.StatusEnded, 1, 3, false))
	headers := func() map[string]string {
		return map[string]string{"Authorization": "Bearer " + e.bearer, "Content-Type": "application/json", "X-Timezone": "Pacific/Kiritimati"}
	}
	rec := e.harness.send(http.MethodPut, "/v1/library/items/"+id+"/episodes/1/1", headers(), `{"watched":true}`)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	zone, err := time.LoadLocation("Pacific/Kiritimati")
	require.NoError(t, err)
	days, err := e.server.Gamification.StreakDays(context.Background(), e.user)
	require.NoError(t, err)
	require.Len(t, days, 1)
	assert.Equal(t, core.LocalDate(time.Now(), zone), days[0].Date)
	assert.Equal(t, "Pacific/Kiritimati", days[0].TimeZone)
	stored, err := e.server.Gamification.TimeZone(context.Background(), e.user)
	require.NoError(t, err)
	assert.Equal(t, "Pacific/Kiritimati", stored.String(), "a later request without the header uses the stored zone")

	rec = e.harness.send(http.MethodGet, "/v1/me/progress", headers(), "")
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	streak := decode[map[string]any](t, rec)["streak"].(map[string]any)
	assert.InDelta(t, 1.0, streak["current"], 0)
	assert.Equal(t, true, streak["today"])
	assert.Len(t, streak["days"], 7)
}

// liveBadge
func TestRouteALiveFinishShowsAnUnseenBadgeOnce(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	e.add("movie", e.stubMovie("Arrival"), "finished")
	assert.Equal(t, 25, e.pointsG6())
	origin, badges, ids := e.unseenBadgesG6()
	assert.Equal(t, "live", origin)
	assert.Contains(t, badges, "first_film")

	items := e.json(http.MethodGet, "/v1/me/badges", nil)["items"].([]any)
	byID := map[string]map[string]any{}
	for _, it := range items {
		b := it.(map[string]any)
		byID[b["id"].(string)] = b
	}
	assert.Equal(t, map[string]any{"current": 1.0, "target": 10.0}, byID["films"]["progress"])
	secret := byID["silver_screen"]
	assert.NotContains(t, secret, "name", "a hidden badge not yet earned says nothing")
	assert.NotContains(t, secret, "description")
	assert.NotContains(t, secret, "progress")

	rec := e.send(http.MethodPost, "/v1/me/badges/seen", map[string]any{"ids": ids})
	require.Equal(t, http.StatusNoContent, rec.Code, rec.Body.String())
	_, badges, _ = e.unseenBadgesG6()
	assert.Empty(t, badges)
	again, err := e.server.Gamification.Evaluate(context.Background(), e.user, gamification.OriginLive, nil)
	require.NoError(t, err)
	assert.Empty(t, again)
}

// undoTakesBadgeBack
func TestRouteUndoingTheActionThatEarnedATierTakesItBack(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	e.add("movie", e.stubMovie("Heat"), "finished")
	assert.True(t, e.earnedBadgeG6("first_film"))
	e.undoLastG6()
	assert.False(t, e.earnedBadgeG6("first_film"))
}

// backfill
func TestRouteFirstRunIsOneBackfill(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	e.add("movie", e.stubMovie("Casablanca"), "finished")
	// As if the account predates achievements: never evaluated, nothing earned.
	ctx := context.Background()
	_, err := e.pool.Exec(ctx, `UPDATE user_progress SET evaluated_at = NULL WHERE user_id = $1`, e.user)
	require.NoError(t, err)
	_, err = e.pool.Exec(ctx, `DELETE FROM user_badges WHERE user_id = $1`, e.user)
	require.NoError(t, err)
	worker := gamification.NewWorker(e.server.Gamification)
	worker.Pace = 0
	claimed := false
	for i := 0; i < 50 && !claimed; i++ {
		_, err := worker.Step(ctx)
		require.NoError(t, err)
		fresh, err := e.server.Gamification.IsFresh(ctx, e.user)
		require.NoError(t, err)
		claimed = !fresh
	}
	assert.True(t, claimed)
	origin, badges, _ := e.unseenBadgesG6()
	assert.Equal(t, "backfill", origin)
	assert.Contains(t, badges, "first_film")
}

// LeaderboardTests.swift

func (e *libEnv) boardHandlesG6(bearer ...string) (optedIn bool, handles []string) {
	e.t.Helper()
	rec := e.send(http.MethodGet, "/v1/social/leaderboard", nil, bearer...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	board := decode[map[string]any](e.t, rec)
	for _, it := range board["entries"].([]any) {
		handles = append(handles, it.(map[string]any)["user"].(map[string]any)["handle"].(string))
	}
	return board["optedIn"].(bool), handles
}

func (e *libEnv) joinBoardG6(bearer ...string) {
	e.t.Helper()
	rec := e.send(http.MethodPut, "/v1/me/social-settings", map[string]any{"shareLibraryWithFriends": true, "leaderboardOptIn": true}, bearer...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
}

// optInAndBlocks
func TestRouteLeaderboardNobodyAppearsUntilTheyJoinBlocksHideBothWays(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	ana := e.friendsByInvite()
	mine := e.json(http.MethodGet, "/v1/me", nil)["handle"].(string)

	optedIn, handles := e.boardHandlesG6()
	assert.False(t, optedIn)
	assert.Empty(t, handles)
	e.joinBoardG6()
	optedIn, handles = e.boardHandlesG6()
	assert.True(t, optedIn)
	assert.Equal(t, []string{mine}, handles, "a friend who has not joined never appears")
	_, handles = e.boardHandlesG6(ana.token)
	assert.Empty(t, handles, "nor does anyone, to someone not joined")

	e.joinBoardG6(ana.token)
	_, handles = e.boardHandlesG6()
	assert.ElementsMatch(t, []string{mine, ana.handle}, handles)

	rec := e.send(http.MethodPut, "/v1/social/blocks/"+up(ana.id), nil)
	require.Equal(t, http.StatusNoContent, rec.Code, rec.Body.String())
	_, handles = e.boardHandlesG6()
	assert.Equal(t, []string{mine}, handles)
	_, handles = e.boardHandlesG6(ana.token)
	assert.Equal(t, []string{ana.handle}, handles)
}

// boardPoints
func TestRouteLeaderboardFriendPointsStayOffRanksFollowTheWeek(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	ana := e.friendsByInvite()
	e.joinBoardG6()
	e.joinBoardG6(ana.token)
	e.add("movie", e.stubMovie("Alien"), "finished")
	entries := e.json(http.MethodGet, "/v1/social/leaderboard", nil)["entries"].([]any)
	require.Len(t, entries, 2)
	first, last := entries[0].(map[string]any), entries[1].(map[string]any)
	assert.Equal(t, true, first["you"])
	assert.InDelta(t, 25.0, first["points"], 0, "the friend award does not count")
	assert.InDelta(t, 1.0, first["rank"], 0)
	assert.InDelta(t, 0.0, last["points"], 0)
	assert.InDelta(t, 25.0, e.json(http.MethodGet, "/v1/me/progress", nil)["weekPoints"], 0)
	assert.Equal(t, http.StatusBadRequest, e.send(http.MethodGet, "/v1/social/leaderboard?week=bad", nil).Code)
}

// partialSettings
func TestAnOlderAppsSettingsPutLeavesTheNewSwitchesAlone(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	e.joinBoardG6()
	rec := e.send(http.MethodPut, "/v1/me/social-settings", map[string]any{"shareLibraryWithFriends": false})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	settings := decode[map[string]any](t, rec)
	assert.Equal(t, true, settings["leaderboardOptIn"])
	assert.Equal(t, true, settings["showAchievementsToFriends"])
	assert.Equal(t, false, settings["shareLibraryWithFriends"])
}

// friendAchievements
func TestRouteFriendsSeeLevelAndBadgesUnlessSwitchedOffNeverPrivate(t *testing.T) {
	e := newEvaluatedLibEnvG6(t)
	ana := e.friendsByInvite()
	e.add("movie", e.stubMovie("Ran"), "finished")
	for i := 0; i < 10; i++ {
		e.add("movie", e.stubMovie("Owned "+uuid.NewString()), "wishlist")
	}
	ctx := context.Background()
	_, err := e.pool.Exec(ctx, `UPDATE library_items SET is_owned = true WHERE user_id = $1`, e.user)
	require.NoError(t, err)
	_, err = e.server.Gamification.InsertBadges(ctx, []gamification.TierDue{{Badge: "collector", Tier: 1}}, e.user, gamification.OriginLive, nil)
	require.NoError(t, err)

	path := "/v1/social/friends/" + up(e.user) + "/profile"
	rec := e.send(http.MethodGet, path, nil, ana.token)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	achievements := decode[map[string]any](t, rec)["achievements"].(map[string]any)
	var badges []string
	for _, b := range achievements["badges"].([]any) {
		badges = append(badges, b.(map[string]any)["badge"].(string))
	}
	assert.Contains(t, badges, "first_film")
	assert.NotContains(t, badges, "collector", "owned items are never shown to friends")
	assert.InDelta(t, 1.0, achievements["level"], 0)

	rec = e.send(http.MethodPut, "/v1/me/social-settings", map[string]any{"shareLibraryWithFriends": true, "showAchievementsToFriends": false})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	rec = e.send(http.MethodGet, path, nil, ana.token)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.NotContains(t, decode[map[string]any](t, rec), "achievements")
}
