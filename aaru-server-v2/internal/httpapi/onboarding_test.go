package httpapi

import (
	"aaru-go-api/internal/catalog"
	"context"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ONB-001: the first-run flow's end, and the picks it saves.

func TestOnboardingIsPendingUntilTheFirstFinishWhichWins(t *testing.T) {
	env := newLibEnv(t)
	assert.Equal(t, true, env.json(http.MethodGet, "/v1/me", nil)["onboardingPending"], "a new account sees the flow")

	require.Equal(t, http.StatusNoContent, env.send(http.MethodPut, "/v1/me/onboarding", map[string]any{"skipped": true}).Code)
	assert.Equal(t, false, env.json(http.MethodGet, "/v1/me", nil)["onboardingPending"])
	var first time.Time
	var skipped bool
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT onboarded_at, onboarding_skipped FROM users WHERE id = $1`, env.user).Scan(&first, &skipped))
	assert.True(t, skipped)

	require.Equal(t, http.StatusNoContent, env.send(http.MethodPut, "/v1/me/onboarding", map[string]any{"skipped": false}).Code)
	var again time.Time
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT onboarded_at, onboarding_skipped FROM users WHERE id = $1`, env.user).Scan(&again, &skipped))
	assert.True(t, skipped, "the first call wins")
	assert.Equal(t, first, again)

	assert.Equal(t, http.StatusBadRequest, env.send(http.MethodPut, "/v1/me/onboarding", map[string]any{}).Code)
}

func pickRef(typ, tmdb string, status ...string) map[string]any {
	item := map[string]any{"mediaRef": map[string]any{"type": typ, "ids": map[string]string{"tmdb": tmdb}}}
	if len(status) > 0 {
		item["status"] = status[0]
	}
	return item
}

type itemRow struct {
	status     string
	byHand     bool
	finishedAt *time.Time
}

func (e *libEnv) itemRow(id string) itemRow {
	e.t.Helper()
	var r itemRow
	require.NoError(e.t, e.pool.QueryRow(context.Background(),
		`SELECT status, status_by_hand, finished_at FROM library_items WHERE id = $1`, uuid.MustParse(id)).
		Scan(&r.status, &r.byHand, &r.finishedAt))
	return r
}

func TestOnboardingPicksAreOneUndatedActionWithoutPoints(t *testing.T) {
	env := newLibEnv(t)
	planned := env.stubMovie("Arrival")
	seen := env.stubMovie("Heat")
	show := env.stubShow("The Wire", catalog.StatusEnded, 2, 3, false)
	owned := env.stubMovie("Alien")
	ownedItem := env.add("movie", owned, "dropped")
	before := env.actionCount()

	rec := env.send(http.MethodPost, "/v1/onboarding/picks", map[string]any{"items": []any{
		pickRef("movie", planned),
		pickRef("movie", seen, "finished"),
		pickRef("show", show, "finished"),
		pickRef("movie", "no-such-film", "finished"),
		pickRef("movie", owned, "finished"),
		pickRef("movie", planned, "finished"),
	}})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	body := decode[map[string]any](t, rec)
	assert.InDelta(t, 1, body["missed"], 0)
	items := body["items"].([]any)
	require.Len(t, items, 5)
	byIndex := map[int]string{}
	for _, it := range items {
		m := it.(map[string]any)
		byIndex[int(m["index"].(float64))] = m["libraryItemId"].(string)
		assert.NotEmpty(t, m["titleId"])
	}
	assert.NotContains(t, byIndex, 3, "the ref no provider knows is only counted")
	assert.Equal(t, strings.ToUpper(ownedItem), byIndex[4], "a title already in the library comes back as it is")
	assert.Equal(t, byIndex[0], byIndex[5], "a title picked twice is added once")

	assert.Equal(t, before+1, env.actionCount(), "one action for the step")
	actionID := body["actionId"].(string)
	var kind string
	require.NoError(t, env.pool.QueryRow(context.Background(), `SELECT kind FROM actions WHERE id = $1`, uuid.MustParse(actionID)).Scan(&kind))
	assert.Equal(t, "onboarding", kind)

	assert.Equal(t, itemRow{status: "wishlist"}, env.itemRow(byIndex[0]), "a wishlist pick is not set by hand")
	assert.Equal(t, itemRow{status: "finished", byHand: true}, env.itemRow(byIndex[1]), "finished before, not today")
	assert.Equal(t, itemRow{status: "dropped", byHand: true}, env.itemRow(ownedItem), "unchanged")
	assert.Equal(t, "finished", env.itemRow(byIndex[2]).status)
	assert.Equal(t, 6, env.watchedCount(byIndex[2]), "a show picked as watched ticks every aired episode (PROG-005)")
	var dated int
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT count(*)::int FROM episode_progress WHERE library_item_id = $1 AND watched_at_known`, uuid.MustParse(byIndex[2])).Scan(&dated))
	assert.Zero(t, dated, "the ticks carry no date")

	var points, checkIns int
	require.NoError(t, env.pool.QueryRow(context.Background(), `SELECT count(*)::int FROM points_events WHERE user_id = $1`, env.user).Scan(&points))
	require.NoError(t, env.pool.QueryRow(context.Background(), `SELECT count(*)::int FROM check_ins WHERE user_id = $1`, env.user).Scan(&checkIns))
	assert.Zero(t, points, "no points")
	assert.Zero(t, checkIns, "no streak day")

	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+actionID+"/undo", nil).Code)
	var left []uuid.UUID
	rows, err := env.pool.Query(context.Background(), `SELECT id FROM library_items WHERE user_id = $1`, env.user)
	require.NoError(t, err)
	for rows.Next() {
		var id uuid.UUID
		require.NoError(t, rows.Scan(&id))
		left = append(left, id)
	}
	require.NoError(t, rows.Err())
	assert.Equal(t, []uuid.UUID{uuid.MustParse(ownedItem)}, left, "one undo takes every pick back, and only the picks")

	again := decode[map[string]any](t, env.send(http.MethodPost, "/v1/onboarding/picks", map[string]any{"items": []any{pickRef("movie", owned)}}))
	assert.Nil(t, again["actionId"], "nothing new, no action")
}

func TestOnboardingPicksTakeOneToSixty(t *testing.T) {
	env := newLibEnv(t)
	film := env.stubMovie("Heat")
	tooMany := make([]any, 61)
	for i := range tooMany {
		tooMany[i] = pickRef("movie", film)
	}
	rec := env.send(http.MethodPost, "/v1/onboarding/picks", map[string]any{"items": tooMany})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code, rec.Body.String())
	assert.Contains(t, rec.Body.String(), "validation_failed")
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, "/v1/onboarding/picks", map[string]any{"items": []any{}}).Code)
	assert.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/onboarding/picks", map[string]any{"items": tooMany[:60]}).Code)
}

func TestOnboardingRelatedTakesOneToThirty(t *testing.T) {
	env := newLibEnv(t)
	ids := make([]string, 31)
	for i := range ids {
		ids[i] = uuid.NewString()
	}
	rec := env.send(http.MethodPost, "/v1/onboarding/related", map[string]any{"titleIds": ids})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code, rec.Body.String())
	body := env.json(http.MethodPost, "/v1/onboarding/related", map[string]any{"titleIds": ids[:30]})
	assert.Equal(t, []any{}, body["items"], "titles Aaru does not hold have no graph")
	assert.Equal(t, false, body["partial"])
}

func TestOnboardingRowsOfAKindWithoutProvider(t *testing.T) {
	env := newLibEnv(t)
	body := env.json(http.MethodGet, "/v1/onboarding/rows?kind=album", nil)
	assert.Equal(t, []any{}, body["rows"], "no album provider, no rows")
	assert.Equal(t, http.StatusBadRequest, env.send(http.MethodGet, "/v1/onboarding/rows?kind=comic", nil).Code)
}
