package httpapi

import (
	"aaru-go-api/internal/social"
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// InviteTests.swift: friend invite links (SOC-002).

func TestAnInviteIsAOneUseLinkThatPreviewsSignedOutAndBefriends(t *testing.T) {
	e := newSocialEnv(t)
	// No handle, no invite: the friend must see who sent it.
	assert.Equal(t, http.StatusUnprocessableEntity, e.send(http.MethodPost, "/v1/social/invites", map[string]any{}).Code)
	mine := freshHandle()
	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": mine, "displayName": "Fern"})

	created := e.json(http.MethodPost, "/v1/social/invites", map[string]any{})
	invite := created["code"].(string)
	assert.Len(t, invite, social.CodeLength)
	assert.Equal(t, "https://aaruapp.com/i/"+invite, created["url"])

	preview := e.send(http.MethodGet, "/v1/invites/"+invite, nil, signedOut)
	require.Equal(t, http.StatusOK, preview.Code, preview.Body.String())
	body := decode[map[string]any](t, preview)
	inviter := body["inviter"].(map[string]any)
	assert.Equal(t, mine, inviter["handle"])
	assert.Equal(t, "Fern", inviter["displayName"])
	assert.Nil(t, body["relationship"])
	assert.Equal(t, "self", e.get("/v1/invites/"+invite)["relationship"])

	// The invitee needs a handle too, and redeeming your own link is refused.
	_, newcomer := e.signIn()
	noHandle := e.send(http.MethodPost, "/v1/social/invites/"+invite+"/redeem", map[string]any{"addTitle": false}, newcomer)
	assert.Equal(t, "handle_required", decode[map[string]any](t, noHandle)["code"])
	own := e.send(http.MethodPost, "/v1/social/invites/"+invite+"/redeem", map[string]any{"addTitle": false})
	assert.Equal(t, http.StatusConflict, own.Code)
	assert.Equal(t, "own_invite", decode[map[string]any](t, own)["code"])

	ana := e.friendlyUser()
	// A pending request between them is answered by the invite.
	e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": mine}, ana.token)
	assert.Equal(t, "outgoing", e.get("/v1/invites/"+invite, ana.token)["relationship"])
	redeemed := e.send(http.MethodPost, "/v1/social/invites/"+invite+"/redeem", map[string]any{"addTitle": true}, ana.token)
	require.Equal(t, http.StatusOK, redeemed.Code, redeemed.Body.String())
	result := decode[map[string]any](t, redeemed)
	assert.Equal(t, mine, result["friend"].(map[string]any)["handle"])
	assert.Equal(t, false, result["titleAdded"])
	assert.Equal(t, []string{ana.handle}, handlesOf(e.get("/v1/social/friends"), "items"))
	assert.Empty(t, e.get("/v1/social/friend-requests")["incoming"])

	// Spent: everyone else now sees the same dead end as a code that never existed.
	kai := e.friendlyUser()
	spent := e.send(http.MethodGet, "/v1/invites/"+invite, nil, kai.token)
	unknown := e.send(http.MethodGet, "/v1/invites/nothing_here", nil, kai.token)
	assert.Equal(t, http.StatusNotFound, spent.Code)
	assert.Equal(t, unknown.Body.String(), spent.Body.String())
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPost, "/v1/social/invites/"+invite+"/redeem", map[string]any{"addTitle": false}, kai.token).Code)
	assert.NotNil(t, e.get("/v1/social/invites")["items"])
}

func TestAnInvitesTitleLandsOnPlanToWatchOnlyWhenAsked(t *testing.T) {
	e := newSocialEnv(t)
	e.claimHandle()
	tmdb := e.stubMovie("Arrival")
	ref := map[string]any{"title": map[string]any{"type": "movie", "ids": map[string]any{"tmdb": tmdb}}}
	created := e.json(http.MethodPost, "/v1/social/invites", ref)
	assert.Equal(t, "Arrival", created["title"].(map[string]any)["title"])
	invite := created["code"].(string)
	preview := decode[map[string]any](t, e.send(http.MethodGet, "/v1/invites/"+invite, nil, signedOut))
	assert.Equal(t, "Arrival", preview["title"].(map[string]any)["title"])

	ana := e.friendlyUser()
	redeemed := decode[map[string]any](t, e.send(http.MethodPost, "/v1/social/invites/"+invite+"/redeem", map[string]any{"addTitle": true}, ana.token))
	assert.Equal(t, true, redeemed["titleAdded"])
	items := rows(t, e.get("/v1/library/items", ana.token))
	require.Len(t, items, 1)
	assert.Equal(t, "wishlist", items[0]["status"])

	// Someone who already has it keeps their own status.
	second := e.json(http.MethodPost, "/v1/social/invites", ref)["code"].(string)
	kai := e.friendlyUser()
	e.addItem("movie", tmdb, "finished", kai.token)
	kept := decode[map[string]any](t, e.send(http.MethodPost, "/v1/social/invites/"+second+"/redeem", map[string]any{"addTitle": true}, kai.token))
	assert.Equal(t, false, kept["titleAdded"])
	assert.Equal(t, "finished", rows(t, e.get("/v1/library/items", kai.token))[0]["status"])
}

func TestRevokedExpiredAndBlockedInvitesReadAsInvalid(t *testing.T) {
	e := newSocialEnv(t)
	mine := e.claimHandle()
	ana := e.friendlyUser()

	revoked := e.json(http.MethodPost, "/v1/social/invites", map[string]any{})["code"].(string)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodDelete, "/v1/social/invites/"+revoked, nil, ana.token).Code)
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/social/invites/"+revoked, nil).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/invites/"+revoked, nil, signedOut).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodDelete, "/v1/social/invites/"+revoked, nil).Code)

	now := time.Now()
	expired := social.NewCode()
	require.NoError(t, e.server.Social.Store.CreateInvite(context.Background(), social.Invite{
		ID: uuid.New(), Code: expired, Inviter: e.user, CreatedAt: now.Add(-social.InviteLifetime - time.Minute),
		ExpiresAt: now.Add(-time.Minute),
	}))
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/invites/"+expired, nil, signedOut).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPost, "/v1/social/invites/"+expired+"/redeem", map[string]any{"addTitle": false}, ana.token).Code)

	// A block either way hides the invite from the blocked side.
	blocked := e.json(http.MethodPost, "/v1/social/invites", map[string]any{})["code"].(string)
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodPut, "/v1/social/blocks/"+ana.idString(), nil).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/invites/"+blocked, nil, ana.token).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPost, "/v1/social/invites/"+blocked+"/redeem", map[string]any{"addTitle": false}, ana.token).Code)
	assert.Equal(t, http.StatusOK, e.send(http.MethodGet, "/v1/invites/"+blocked, nil, signedOut).Code)
	e.send(http.MethodDelete, "/v1/social/blocks/"+ana.idString(), nil)

	// Already friends: a success that leaves the link for someone else.
	e.befriend(mine, ana)
	assert.Equal(t, http.StatusOK, e.send(http.MethodPost, "/v1/social/invites/"+blocked+"/redeem", map[string]any{"addTitle": false}, ana.token).Code)
	assert.Equal(t, http.StatusOK, e.send(http.MethodGet, "/v1/invites/"+blocked, nil, signedOut).Code)
	open := rows(t, e.get("/v1/social/invites"))
	require.Len(t, open, 1)
	assert.Equal(t, blocked, open[0]["code"])
}

func TestOpenInvitesAreCapped(t *testing.T) {
	e := newSocialEnv(t)
	e.claimHandle()
	for range social.MaxOpenInvites {
		require.Equal(t, http.StatusOK, e.send(http.MethodPost, "/v1/social/invites", map[string]any{}).Code)
	}
	over := e.send(http.MethodPost, "/v1/social/invites", map[string]any{})
	assert.Equal(t, http.StatusUnprocessableEntity, over.Code)
	assert.Equal(t, "too_many_invites", decode[map[string]any](t, over)["code"])
}
