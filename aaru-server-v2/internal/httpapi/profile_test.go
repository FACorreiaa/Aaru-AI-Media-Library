package httpapi

import (
	"aaru-go-api/internal/social"
	"context"
	"encoding/base64"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ProfileTests.swift: names, avatar and email (SOC-001b).

// smallJPEG is the smallest bytes the server takes for a JPEG: its magic number.
var smallJPEG = []byte{0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4}

func TestFirstAndLastNameAreSavedJoinedAndKeptWhenLeftOut(t *testing.T) {
	e := newSocialEnv(t)
	// No handle needed for a name.
	saved := e.json(http.MethodPut, "/v1/me/profile", map[string]any{"firstName": " Ana ", "lastName": "Lopes"})
	assert.Equal(t, "Ana Lopes", saved["displayName"])
	assert.Nil(t, saved["handle"])

	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"lastName": "Silva"})
	account := e.get("/v1/me")
	assert.Equal(t, "Ana", account["firstName"])
	assert.Equal(t, "Silva", account["lastName"])

	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"firstName": ""})
	account = e.get("/v1/me")
	assert.Nil(t, account["firstName"])
	assert.Equal(t, "Silva", account["displayName"])

	refused := e.send(http.MethodPut, "/v1/me/profile", map[string]any{"lastName": strings.Repeat("a", social.MaxDisplayNameLength+1)})
	assert.Equal(t, http.StatusUnprocessableEntity, refused.Code)
	assert.NotNil(t, decode[map[string]any](t, refused)["details"].(map[string]any)["lastName"])
}

func TestAnOlderAppsDisplayNameIsNoChangeWhenItMatches(t *testing.T) {
	e := newSocialEnv(t)
	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": freshHandle(), "firstName": "Mary Ann", "lastName": "Smith"})
	// An old app saving only its handle still sends the name it read.
	renamed := freshHandle()
	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": renamed, "displayName": "Mary Ann Smith"})
	account := e.get("/v1/me")
	assert.Equal(t, renamed, account["handle"])
	assert.Equal(t, "Mary Ann", account["firstName"])
	assert.Equal(t, "Smith", account["lastName"])

	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": renamed, "displayName": "Ana Lopes"})
	account = e.get("/v1/me")
	assert.Equal(t, "Ana", account["firstName"])
	assert.Equal(t, "Lopes", account["lastName"])

	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": renamed, "displayName": ""})
	account = e.get("/v1/me")
	assert.Nil(t, account["firstName"])
	assert.Nil(t, account["displayName"])
}

func TestAnAvatarIsAJPEGUnder1MB(t *testing.T) {
	e := newSocialEnv(t)
	png := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}
	assert.Equal(t, http.StatusUnsupportedMediaType, e.uploadAvatar(png, "image/jpeg").Code)
	assert.Equal(t, http.StatusUnsupportedMediaType, e.uploadAvatar(png, "image/png").Code)
	huge := append(append([]byte{}, smallJPEG...), make([]byte, social.MaxAvatarBytes)...)
	tooLarge := e.uploadAvatar(huge, "image/jpeg")
	assert.Equal(t, http.StatusRequestEntityTooLarge, tooLarge.Code)
	assert.Equal(t, "file_too_large", decode[map[string]any](t, tooLarge)["code"])
	assert.Nil(t, e.get("/v1/me")["avatarUrl"])

	saved := e.uploadAvatar(smallJPEG, "image/jpeg")
	require.Equal(t, http.StatusOK, saved.Code, saved.Body.String())
	path := decode[map[string]any](t, saved)["avatarUrl"].(string)
	assert.True(t, strings.HasPrefix(path, "/v1/users/"+strings.ToUpper(e.user.String())+"/avatar?v="), path)

	image := e.send(http.MethodGet, path, nil)
	assert.Equal(t, http.StatusOK, image.Code)
	assert.Equal(t, smallJPEG, image.Body.Bytes())
	assert.Equal(t, "image/jpeg", image.Header().Get("Content-Type"))
	assert.Equal(t, "private, max-age=604800", image.Header().Get("Cache-Control"))

	// A new photo is a new URL, so no cache serves the old one.
	again := e.uploadAvatar(append(append([]byte{}, smallJPEG...), 5), "image/jpeg")
	assert.NotEqual(t, path, decode[map[string]any](t, again)["avatarUrl"])

	removed := e.send(http.MethodDelete, "/v1/me/avatar", nil)
	assert.Equal(t, http.StatusOK, removed.Code)
	assert.Nil(t, decode[map[string]any](t, removed)["avatarUrl"])
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, path, nil).Code)
}

func TestAnAvatarShowsToAnyoneSignedInNeverSignedOutBlockedOrOnTheInvitePreview(t *testing.T) {
	e := newSocialEnv(t)
	mine := e.claimHandle()
	path := decode[map[string]any](t, e.uploadAvatar(smallJPEG, "image/jpeg"))["avatarUrl"].(string)
	ana := e.friendByRequest(mine)

	assert.Equal(t, http.StatusOK, e.send(http.MethodGet, path, nil, ana.token).Code)
	_, stranger := e.signIn()
	assert.Equal(t, http.StatusOK, e.send(http.MethodGet, path, nil, stranger).Code)
	assert.Equal(t, http.StatusUnauthorized, e.send(http.MethodGet, path, nil, signedOut).Code)

	listed := rows(t, e.get("/v1/social/friends", ana.token))
	require.Len(t, listed, 1)
	assert.Equal(t, path, listed[0]["avatarUrl"])

	code := e.json(http.MethodPost, "/v1/social/invites", map[string]any{})["code"].(string)
	preview := decode[map[string]any](t, e.send(http.MethodGet, "/v1/invites/"+code, nil, signedOut))
	inviter := preview["inviter"].(map[string]any)
	assert.Equal(t, mine, inviter["handle"])
	assert.Nil(t, inviter["avatarUrl"])

	// A block either way is the same 404 as no avatar.
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodPut, "/v1/social/blocks/"+ana.idString(), nil).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, path, nil, ana.token).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/users/"+uuid.NewString()+"/avatar", nil).Code)
}

func TestFriendsSeeTheEmailOnlyWhileShared(t *testing.T) {
	e := newSocialEnv(t)
	mine := e.claimHandle()
	address := strings.ToLower(uuid.NewString()) + "@example.com"
	token := e.userWithEmail("email", address)
	theirs := freshHandle()
	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": theirs}, token)
	e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": theirs})
	e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": mine}, token)
	account := e.get("/v1/me", token)
	id := account["userId"].(string)
	assert.Equal(t, address, account["email"])
	assert.Equal(t, true, account["emailShareable"])

	profilePath := "/v1/social/friends/" + id + "/profile"
	assert.Nil(t, e.get(profilePath)["email"])
	assert.Equal(t, false, e.get("/v1/me/social-settings", token)["shareEmailWithFriends"])

	// A partial PUT, as older apps send, keeps the other switches.
	e.send(http.MethodPut, "/v1/me/social-settings", map[string]any{"shareLibraryWithFriends": false, "shareEmailWithFriends": true}, token)
	assert.Equal(t, address, e.get(profilePath)["email"])
	e.send(http.MethodPut, "/v1/me/social-settings", map[string]any{"shareLibraryWithFriends": true}, token)
	assert.Equal(t, true, e.get("/v1/me/social-settings", token)["shareEmailWithFriends"])

	relay := e.userWithEmail("apple", "abc@privaterelay.appleid.com")
	hidden := e.get("/v1/me", relay)
	assert.Equal(t, "abc@privaterelay.appleid.com", hidden["email"])
	assert.Equal(t, false, hidden["emailShareable"])
}

func TestTheExportCarriesNamesAndAvatarAndDeleteTakesTheAvatar(t *testing.T) {
	e := newSocialEnv(t)
	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"firstName": "Ana", "lastName": "Lopes"})
	e.uploadAvatar(smallJPEG, "image/jpeg")
	export := e.get("/v1/me/export")
	account := export["account"].(map[string]any)
	assert.Equal(t, "Ana", account["firstName"])
	assert.Equal(t, "Lopes", account["lastName"])
	assert.Equal(t, base64.StdEncoding.EncodeToString(smallJPEG), export["avatarJpeg"])

	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/me", nil).Code)
	image, err := e.server.Social.Store.Avatar(context.Background(), e.user)
	require.NoError(t, err)
	assert.Nil(t, image)
}
