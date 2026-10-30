package httpapi

import (
	"context"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Ported from MangaTests.swift (add, labelsAndFilter): a manga added by its AniList id carries its
// author and counts, and reads Plan to read, Reading, Read in the journal.
func TestMangaAddedByAniListReadsPlanReadingRead(t *testing.T) {
	env := newLibEnv(t)
	added := env.json(http.MethodPost, "/v1/library/items", map[string]any{
		"mediaRef": map[string]any{"type": "manga", "ids": map[string]string{"anilist": env.stubManga("Vagabond")}},
	})
	title := added["title"].(map[string]any)
	assert.Equal(t, "manga", title["type"])
	assert.Equal(t, false, title["isAnime"])
	assert.Equal(t, "Kentarou Miura", title["byline"])
	assert.InDelta(t, 364, title["chapterCount"], 0)
	assert.InDelta(t, 41, title["volumeCount"], 0)
	assert.Equal(t, "wishlist", added["status"])
	item := added["id"].(string)

	env.json(http.MethodPatch, patchPath(item), map[string]any{"status": "in_progress"})
	env.json(http.MethodPatch, patchPath(item), map[string]any{"status": "finished"})
	assert.Equal(t, []string{
		"Moved Vagabond to Read", "Moved Vagabond to Reading", "Added Vagabond to Plan to read",
	}, summaries(env))
	assert.Equal(t, []string{item}, ids(env.json(http.MethodGet, "/v1/library/items?type=manga", nil)["items"]))
}

// Ported from SportsTests.swift (isolation): sports stay in Sports. No library row, action, point or
// activity; the export carries them.
func TestSportsStayInSportsAndTheExportCarriesThem(t *testing.T) {
	h := newHarness(t, withSports(sportsProvider()))
	userID, bearer := h.signIn()
	before := rowsReferencing(t, h, userID)
	require.Equal(t, http.StatusOK, h.do(http.MethodPut, "/v1/me/sport-follows/team/133604", bearer, nil).Code)
	require.Equal(t, http.StatusOK, h.do(http.MethodPut, "/v1/me/sport-settings", bearer, map[string]any{"watchCountryCode": "PT"}).Code)
	require.Equal(t, http.StatusOK, h.do(http.MethodGet, "/v1/sports/favorites", bearer, nil).Code)
	after := rowsReferencing(t, h, userID)
	var touched []string
	for key, n := range after {
		if before[key] != n {
			touched = append(touched, key)
		}
	}
	assert.ElementsMatch(t, []string{"sport_follows.user_id", "sport_settings.user_id"}, touched)
	var actions int
	require.NoError(t, h.pool.QueryRow(context.Background(), `SELECT count(*)::int FROM actions WHERE user_id = $1`, userID).Scan(&actions))
	assert.Zero(t, actions)

	export := decode[map[string]any](t, h.do(http.MethodGet, "/v1/me/export", bearer, nil))
	sportsBlock := export["sports"].(map[string]any)
	follows := sportsBlock["follows"].([]any)
	require.NotEmpty(t, follows)
	assert.Equal(t, "133604", follows[0].(map[string]any)["id"])
	assert.Equal(t, "PT", sportsBlock["watchCountryCode"])
}
