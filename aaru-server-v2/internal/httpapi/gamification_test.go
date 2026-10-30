package httpapi

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/gamification"
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// finishMovie adds a finished movie as a live write, the way the library will.
func (h *harness) finishMovie(user uuid.UUID) uuid.UUID {
	h.t.Helper()
	ctx := context.Background()
	title, item, action := uuid.New(), uuid.New(), uuid.New()
	_, err := h.pool.Exec(ctx, `INSERT INTO titles (id, type, title, tmdb) VALUES ($1, 'movie', 'Arrival', '329865')`, title)
	require.NoError(h.t, err)
	_, err = h.pool.Exec(ctx, `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at) VALUES ($1, $2, $3, 'finished', now(), now())`, item, user, title)
	require.NoError(h.t, err)
	_, err = h.pool.Exec(ctx, `INSERT INTO actions (id, user_id, actor, kind, summary, inverse) VALUES ($1, $2, 'user', 'add', 'Added', '{}')`, action, user)
	require.NoError(h.t, err)
	facts := gamification.NewWriteFacts("add")
	facts.Inserted(item, core.StatusFinished)
	require.NoError(h.t, pgx.BeginFunc(ctx, h.pool, func(tx pgx.Tx) error {
		return gamification.RecordLibraryWrite(ctx, tx, gamification.LibraryWrite{Facts: facts, ActionID: action, UserID: user})
	}))
	h.server.Gamification.AfterWrite(ctx, user, &action)
	return title
}

// evaluated marks the user as signed up after achievements (sign-up does this).
func (h *harness) evaluated(user uuid.UUID) {
	_, err := h.pool.Exec(context.Background(), `INSERT INTO user_progress (user_id, evaluated_at) VALUES ($1, now())`, user)
	require.NoError(h.t, err)
}

func TestProgressBadgesAndSeen(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	h.evaluated(user)
	h.finishMovie(user)

	rec := h.do(http.MethodGet, "/v1/me/progress", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	progress := decode[map[string]any](t, rec)
	assert.EqualValues(t, 25, progress["total"])
	assert.EqualValues(t, 1, progress["level"])
	assert.EqualValues(t, 0, progress["levelStart"])
	assert.EqualValues(t, 100, progress["nextLevelAt"])
	assert.EqualValues(t, 25, progress["weekPoints"])
	streak := progress["streak"].(map[string]any)
	assert.EqualValues(t, 1, streak["current"])
	assert.Equal(t, true, streak["today"])
	assert.Len(t, streak["days"], 7)
	unseen := progress["unseen"].(map[string]any)
	assert.Equal(t, "live", unseen["origin"])
	items := unseen["items"].([]any)
	var ids []string
	var badges []string
	for _, it := range items {
		award := it.(map[string]any)
		ids = append(ids, award["id"].(string))
		badges = append(badges, award["badge"].(string))
		assert.Equal(t, strings.ToUpper(award["id"].(string)), award["id"], "ids are uppercase")
	}
	assert.Contains(t, badges, "first_film")

	rec = h.do(http.MethodGet, "/v1/me/badges", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	list := decode[struct {
		Items []map[string]any `json:"items"`
	}](t, rec)
	byID := map[string]map[string]any{}
	for _, b := range list.Items {
		byID[b["id"].(string)] = b
	}
	films := byID["films"]
	assert.Equal(t, map[string]any{"current": float64(1), "target": float64(10)}, films["progress"])
	assert.Equal(t, "Finish 10 films", films["description"])
	assert.Len(t, films["tiers"], 4)
	secret := byID["silver_screen"]
	assert.NotContains(t, secret, "name", "a hidden badge not yet earned says nothing")
	assert.NotContains(t, secret, "description")
	assert.NotContains(t, secret, "progress")
	assert.Equal(t, []any{}, secret["tiers"])
	assert.Equal(t, true, byID["collector"]["private"])
	assert.NotContains(t, byID["films"], "private")
	first := byID["first_film"]
	assert.Equal(t, true, first["earned"])
	assert.EqualValues(t, 1, first["tier"])
	assert.NotContains(t, first, "progress", "every tier earned")

	tooMany := make([]string, 201)
	for i := range tooMany {
		tooMany[i] = uuid.NewString()
	}
	rec = h.do(http.MethodPost, "/v1/me/badges/seen", bearer, map[string]any{"ids": tooMany})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code, rec.Body.String())
	assert.Contains(t, rec.Body.String(), "Send at most 200 ids.")

	rec = h.do(http.MethodPost, "/v1/me/badges/seen", bearer, map[string]any{"ids": append(ids, "nonsense")})
	require.Equal(t, http.StatusNoContent, rec.Code, rec.Body.String())
	progress = decode[map[string]any](t, h.do(http.MethodGet, "/v1/me/progress", bearer, nil))
	assert.EqualValues(t, 0, progress["unseen"].(map[string]any)["count"])
}

func TestPointsLedgerPage(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	h.evaluated(user)
	title := h.finishMovie(user)

	rec := h.do(http.MethodGet, "/v1/me/points?limit=1", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	page := decode[map[string]any](t, rec)
	items := page["items"].([]any)
	require.Len(t, items, 1)
	event := items[0].(map[string]any)
	assert.Equal(t, "movie_finished", event["kind"])
	assert.EqualValues(t, 25, event["points"])
	assert.Equal(t, false, event["revocation"])
	assert.Regexp(t, `^\d{4}-\d{2}-\d{2}$`, event["day"])
	summary := event["title"].(map[string]any)
	assert.Equal(t, strings.ToUpper(title.String()), summary["id"])
	assert.Equal(t, "329865", summary["ids"].(map[string]any)["tmdb"])
	assert.Contains(t, page, "nextBefore", "a full page has a next page")

	page = decode[map[string]any](t, h.do(http.MethodGet, "/v1/me/points", bearer, nil))
	assert.Len(t, page["items"], 1)
	assert.NotContains(t, page, "nextBefore")
}

func TestLeaderboardRoute(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	h.evaluated(user)
	ctx := context.Background()
	_, err := h.pool.Exec(ctx, `INSERT INTO profiles (user_id, handle) VALUES ($1, 'me_handle')`, user)
	require.NoError(t, err)
	_, err = h.pool.Exec(ctx, `UPDATE users SET avatar_version = 3 WHERE id = $1`, user)
	require.NoError(t, err)

	board := decode[map[string]any](t, h.do(http.MethodGet, "/v1/social/leaderboard", bearer, nil))
	assert.Equal(t, false, board["optedIn"])
	assert.Equal(t, []any{}, board["entries"])
	assert.Regexp(t, `^\d{4}-W\d{2}$`, board["week"])

	_, err = h.pool.Exec(ctx, `INSERT INTO social_settings (user_id, leaderboard_opt_in) VALUES ($1, true)`, user)
	require.NoError(t, err)
	h.finishMovie(user)
	rec := h.do(http.MethodGet, "/v1/social/leaderboard?week=2026-W43", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	board = decode[map[string]any](t, rec)
	assert.Equal(t, "2026-W43", board["week"])
	assert.Equal(t, "2026-10-19", board["from"])
	assert.Equal(t, "2026-10-25", board["until"])
	board = decode[map[string]any](t, h.do(http.MethodGet, "/v1/social/leaderboard", bearer, nil))
	entries := board["entries"].([]any)
	require.Len(t, entries, 1)
	entry := entries[0].(map[string]any)
	assert.Equal(t, true, entry["you"])
	assert.EqualValues(t, 25, entry["points"])
	assert.EqualValues(t, 1, entry["rank"])
	person := entry["user"].(map[string]any)
	assert.Equal(t, "me_handle", person["handle"])
	assert.Equal(t, "/v1/users/"+strings.ToUpper(user.String())+"/avatar?v=3", person["avatarUrl"])

	rec = h.do(http.MethodGet, "/v1/social/leaderboard?week=bad", bearer, nil)
	assert.Equal(t, http.StatusBadRequest, rec.Code)
	assert.Contains(t, rec.Body.String(), "Weeks look like 2026-W43.")

	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/me/progress", "", nil).Code)
}
