package httpapi

import (
	"aaru-go-api/internal/tonight"
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Ported from TonightHTTPTests (TonightTests.swift).

// tonightShow is a show in progress with six aired episodes, none watched.
func (h *harness) tonightShow(user uuid.UUID, name string) uuid.UUID {
	return h.addItem(user, h.seedShow(name, false, "returning", 50, -36, -35, -34, -33, -32, -31), "in_progress", true)
}

func (h *harness) tonightPicks(bearer string) []string {
	h.t.Helper()
	rec := h.do(http.MethodGet, "/v1/tonight?tz=Europe/Lisbon", bearer, nil)
	require.Equal(h.t, http.StatusOK, rec.Code, rec.Body.String())
	body := decode[obj](h.t, rec)
	ids := []string{}
	for _, p := range body["picks"].([]any) {
		ids = append(ids, strings.ToLower(p.(obj)["libraryItemId"].(string)))
	}
	return ids
}

func TestTonightFeedbackRoundTrip(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	first, second := h.tonightShow(user, "Severance"), h.tonightShow(user, "Andor")

	rec := h.do(http.MethodGet, "/v1/tonight?tz=Europe/Lisbon", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code)
	body := decode[obj](t, rec)
	assert.Regexp(t, `^\d{4}-\d{2}-\d{2}$`, body["day"])
	for _, p := range body["picks"].([]any) {
		pick := p.(obj)
		assert.Equal(t, "50 min · 6 left", pick["reason"])
		assert.Equal(t, "continue", pick["kind"])
		assert.Equal(t, obj{"season": 1.0, "number": 1.0}, pick["episode"])
	}
	assert.ElementsMatch(t, []string{first.String(), second.String()}, h.tonightPicks(bearer))

	hide := h.do(http.MethodPost, "/v1/tonight/"+first.String()+"/feedback?tz=Europe/Lisbon", bearer, obj{"verdict": "not_tonight"})
	assert.Equal(t, http.StatusNoContent, hide.Code, hide.Body.String())
	assert.Equal(t, []string{second.String()}, h.tonightPicks(bearer))

	// Someone else's item, or nonsense, is not found.
	_, other := h.signIn()
	foreign := h.do(http.MethodPost, "/v1/tonight/"+second.String()+"/feedback", other, obj{"verdict": "rejected"})
	assert.Equal(t, http.StatusNotFound, foreign.Code)
	assert.Equal(t, "No such library item.", decode[obj](t, foreign)["message"])
	nonsense := h.do(http.MethodPost, "/v1/tonight/nonsense/feedback", bearer, obj{"verdict": "rejected"})
	assert.Equal(t, http.StatusNotFound, nonsense.Code)
	badZone := h.do(http.MethodGet, "/v1/tonight?tz=Mars/Olympus", bearer, nil)
	assert.Equal(t, http.StatusUnprocessableEntity, badZone.Code)
	assert.Equal(t, "Use an IANA time zone such as Europe/Lisbon.", decode[obj](t, badZone)["details"].(obj)["tz"])

	// Progress on a shown pick counts it taken (the library's hook).
	ctx := context.Background()
	require.NoError(t, tonight.AcceptPicks(ctx, h.server.q, user, []uuid.UUID{second}))
	require.NoError(t, tonight.AcceptPicks(ctx, h.server.q, user, []uuid.UUID{second}))
	var taken int
	require.NoError(t, h.pool.QueryRow(ctx, `SELECT count(*)::int FROM tonight_picks WHERE user_id = $1 AND accepted_at IS NOT NULL`, user).Scan(&taken))
	assert.Equal(t, 1, taken)
}

func TestTonightUndo(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	first, second := h.tonightShow(user, "Severance"), h.tonightShow(user, "Andor")
	h.do(http.MethodPost, "/v1/tonight/"+first.String()+"/feedback?tz=Europe/Lisbon", bearer, obj{"verdict": "not_tonight"})
	assert.Equal(t, []string{second.String()}, h.tonightPicks(bearer))

	// Someone else clearing it changes nothing.
	_, other := h.signIn()
	foreign := h.do(http.MethodDelete, "/v1/tonight/"+first.String()+"/feedback", other, nil)
	assert.Equal(t, http.StatusNoContent, foreign.Code)
	assert.Equal(t, []string{second.String()}, h.tonightPicks(bearer))

	undo := h.do(http.MethodDelete, "/v1/tonight/"+first.String()+"/feedback?tz=Europe/Lisbon", bearer, nil)
	assert.Equal(t, http.StatusNoContent, undo.Code)
	assert.ElementsMatch(t, []string{first.String(), second.String()}, h.tonightPicks(bearer))
	again := h.do(http.MethodDelete, "/v1/tonight/"+first.String()+"/feedback?tz=Europe/Lisbon", bearer, nil)
	assert.Equal(t, http.StatusNoContent, again.Code)
}

func TestTonightEmpty(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	assert.Empty(t, h.tonightPicks(bearer))
	var rows int
	require.NoError(t, h.pool.QueryRow(context.Background(), `SELECT count(*)::int FROM tonight_picks`).Scan(&rows))
	assert.Zero(t, rows, "an empty strip records nothing")
}
