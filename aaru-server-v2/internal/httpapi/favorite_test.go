package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"fmt"
	"net/http"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// FavoritesTests.swift: FAV-001, an ordered top 10 per kind, any catalog title, shown to friends
// who may see the library.

func film(tmdb string) map[string]any {
	return map[string]any{"type": "movie", "ids": map[string]any{"tmdb": tmdb}}
}

func TestAFavoriteKindIsSetReorderedAndCleared(t *testing.T) {
	e := newSocialEnv(t)
	arrival, dune, heat := e.stubMovie("Arrival"), e.stubMovie("Dune"), e.stubMovie("Heat")
	empty := e.get("/v1/me/favorites")
	for _, kind := range []string{"film", "show", "anime", "manga", "book", "album"} {
		assert.NotNil(t, empty[kind], kind)
		assert.Empty(t, names(empty[kind]), kind)
	}

	set := e.send(http.MethodPut, "/v1/me/favorites/film", map[string]any{"items": []any{film(arrival), film(dune), film(heat)}})
	require.Equal(t, http.StatusOK, set.Code, set.Body.String())
	assert.Equal(t, []string{"Arrival", "Dune", "Heat"}, names(decode[map[string]any](t, set)["film"]))
	assert.Empty(t, e.get("/v1/library/sync")["items"], "a favorite is not a library write")

	reordered := e.json(http.MethodPut, "/v1/me/favorites/film", map[string]any{"items": []any{film(heat), film(arrival)}})
	assert.Equal(t, []string{"Heat", "Arrival"}, names(reordered["film"]))
	assert.Equal(t, []string{"Heat", "Arrival"}, names(e.get("/v1/me/favorites")["film"]))

	cleared := e.json(http.MethodPut, "/v1/me/favorites/film", map[string]any{"items": []any{}})
	assert.Empty(t, names(cleared["film"]))
}

func TestFavoritesValidation(t *testing.T) {
	e := newSocialEnv(t)
	arrival := e.stubMovie("Arrival")
	e.send(http.MethodPut, "/v1/me/favorites/film", map[string]any{"items": []any{film(arrival)}})

	eleven := []any{}
	for i := range 11 {
		eleven = append(eleven, film(e.stubMovie(fmt.Sprintf("Film %d", i))))
	}
	tooMany := e.send(http.MethodPut, "/v1/me/favorites/film", map[string]any{"items": eleven})
	assert.Equal(t, http.StatusUnprocessableEntity, tooMany.Code)
	assert.Equal(t, "validation_failed", decode[map[string]any](t, tooMany)["code"])

	assert.Equal(t, http.StatusOK, e.send(http.MethodPut, "/v1/me/favorites/film", map[string]any{"items": eleven[:10]}).Code)
	e.send(http.MethodPut, "/v1/me/favorites/film", map[string]any{"items": []any{film(arrival)}})

	twice := e.send(http.MethodPut, "/v1/me/favorites/film", map[string]any{"items": []any{film(arrival), film(arrival)}})
	assert.Equal(t, http.StatusUnprocessableEntity, twice.Code)

	show := e.stubShow("Severance", catalog.StatusReturning, 1, 1, false)
	wrongKind := e.send(http.MethodPut, "/v1/me/favorites/film", map[string]any{"items": []any{map[string]any{"type": "show", "ids": map[string]any{"tmdb": show}}}})
	assert.Equal(t, http.StatusUnprocessableEntity, wrongKind.Code)
	assert.True(t, strings.Contains(decode[map[string]any](t, wrongKind)["message"].(string), "not a film"))
	assert.Equal(t, []string{"Arrival"}, names(e.get("/v1/me/favorites")["film"]))

	unknownKind := e.send(http.MethodPut, "/v1/me/favorites/games", map[string]any{"items": []any{}})
	assert.True(t, unknownKind.Code >= 400 && unknownKind.Code < 500)
}

func TestAnimeIsItsOwnFavoriteKind(t *testing.T) {
	e := newSocialEnv(t)
	anilist := e.fake.uniqueID("al")
	year, runtime := 2023, 24
	status := catalog.StatusEnded
	e.fake.stubTitle(catalog.Record{
		Hit:    catalog.Hit{Type: core.MediaShow, Title: "Frieren", Year: &year, IDs: core.ExternalIDs{AniList: anilist}, IsAnime: true},
		Status: &status, RuntimeMinutes: &runtime,
	})
	frieren := map[string]any{"type": "show", "ids": map[string]any{"anilist": anilist}}
	assert.Equal(t, http.StatusUnprocessableEntity, e.send(http.MethodPut, "/v1/me/favorites/show", map[string]any{"items": []any{frieren}}).Code)
	saved := e.json(http.MethodPut, "/v1/me/favorites/anime", map[string]any{"items": []any{frieren}})
	assert.Equal(t, []string{"Frieren"}, names(saved["anime"]))
	assert.Empty(t, names(saved["show"]))
}

func TestAFriendSeesYourFavoritesOnlyWhileYouShareYourLibrary(t *testing.T) {
	e := newSocialEnv(t)
	ana := e.friendsByInvite()
	heat := e.stubMovie("Heat")
	e.send(http.MethodPut, "/v1/me/favorites/film", map[string]any{"items": []any{film(heat)}}, ana.token)

	shown := e.get("/v1/social/friends/" + ana.idString() + "/profile")
	assert.Equal(t, []string{"Heat"}, names(shown["favorites"].(map[string]any)["film"]))

	e.send(http.MethodPut, "/v1/me/social-settings", map[string]any{"shareLibraryWithFriends": false}, ana.token)
	assert.Nil(t, e.get("/v1/social/friends/" + ana.idString() + "/profile")["favorites"])

	kai := e.friendlyUser()
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/social/friends/"+ana.idString()+"/profile", nil, kai.token).Code)
}

func TestTheExportCarriesFavorites(t *testing.T) {
	e := newSocialEnv(t)
	dune := e.stubMovie("Dune")
	e.send(http.MethodPut, "/v1/me/favorites/film", map[string]any{"items": []any{film(dune)}})
	export := e.get("/v1/me/export")
	assert.Equal(t, []string{"Dune"}, names(export["favorites"].(map[string]any)["film"]))
}
