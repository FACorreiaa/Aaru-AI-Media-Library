package httpapi

import (
	"aaru-go-api/internal/social"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// SocialTests.swift: handles, friends and blocks (SOC-001 / SOC-002 minimal).

func TestHandlesAreValidatedLowercasedUniqueAndShowOnMe(t *testing.T) {
	e := newSocialEnv(t)
	for _, bad := range []string{"ab", "has space", "way_too_long_for_a_handle", "émile", "aaru", "AARU"} {
		assert.Equal(t, http.StatusUnprocessableEntity, e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": bad}).Code, bad)
	}
	handle := freshHandle()
	saved := e.json(http.MethodPut, "/v1/me/profile", map[string]any{"handle": strings.ToUpper(handle), "displayName": " Ana "})
	assert.Equal(t, handle, saved["handle"])
	assert.Equal(t, "Ana", saved["displayName"])
	assert.Equal(t, handle, e.get("/v1/me")["handle"])

	// Absent leaves the name; empty clears it.
	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": handle})
	assert.Equal(t, "Ana", e.get("/v1/me")["displayName"])
	e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": handle, "displayName": ""})
	assert.Nil(t, e.get("/v1/me")["displayName"])

	_, other := e.signIn()
	taken := e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": handle}, other)
	assert.Equal(t, http.StatusConflict, taken.Code)
	assert.Equal(t, "That handle is taken.", decode[map[string]any](t, taken)["message"])
}

func TestFriendRequestAcceptUnfriendAndWithdraw(t *testing.T) {
	e := newSocialEnv(t)
	ana := e.friendlyUser()
	// No handle, no social acts: the other side must see who is asking.
	anonymous := e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": ana.handle})
	assert.Equal(t, http.StatusUnprocessableEntity, anonymous.Code)
	assert.Equal(t, "handle_required", decode[map[string]any](t, anonymous)["code"])

	mine := e.claimHandle()
	assert.Equal(t, http.StatusUnprocessableEntity, e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": mine}).Code)

	sent := e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": ana.handle})
	assert.Equal(t, "outgoing", relationshipOf(t, sent))
	// Asking twice changes nothing.
	assert.Equal(t, "outgoing", relationshipOf(t, e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": ana.handle})))
	assert.Equal(t, "incoming", relationshipOf(t, e.send(http.MethodGet, "/v1/social/users/"+mine, nil, ana.token)))

	inbox := e.get("/v1/social/friend-requests", ana.token)
	incoming := inbox["incoming"].([]any)
	require.Len(t, incoming, 1)
	first := incoming[0].(map[string]any)
	requestID := first["id"].(string)
	assert.Equal(t, strings.ToUpper(requestID), requestID, "ids are uppercase")
	assert.Equal(t, mine, first["user"].(map[string]any)["handle"])

	// Only the recipient accepts.
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPost, "/v1/social/friend-requests/"+requestID+"/accept", nil).Code)
	accepted := e.send(http.MethodPost, "/v1/social/friend-requests/"+requestID+"/accept", nil, ana.token)
	assert.Equal(t, mine, decode[map[string]any](t, accepted)["handle"])
	assert.Equal(t, []string{ana.handle}, handlesOf(e.get("/v1/social/friends"), "items"))
	assert.Equal(t, []string{mine}, handlesOf(e.get("/v1/social/friends", ana.token), "items"))
	assert.Equal(t, "friend", relationshipOf(t, e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": ana.handle})))

	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/social/friends/"+ana.idString(), nil).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodDelete, "/v1/social/friends/"+ana.idString(), nil).Code)
	assert.Empty(t, handlesOf(e.get("/v1/social/friends", ana.token), "items"))

	// Both ask: the second ask is an acceptance.
	e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": ana.handle})
	mutual := e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": mine}, ana.token)
	assert.Equal(t, "friend", relationshipOf(t, mutual))
	assert.Empty(t, e.get("/v1/social/friend-requests")["outgoing"])

	// Withdrawing: the sender cancels, a second time is a 404.
	kai := e.friendlyUser()
	e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": kai.handle})
	outgoing := e.get("/v1/social/friend-requests")["outgoing"].([]any)
	pending := outgoing[0].(map[string]any)["id"].(string)
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/social/friend-requests/"+pending, nil).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodDelete, "/v1/social/friend-requests/"+pending, nil).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/social/users/nobody_has_this", nil).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodDelete, "/v1/social/friend-requests/not-a-uuid", nil).Code)
}

func TestABlockEndsTheFriendshipAndIsA404BothWays(t *testing.T) {
	e := newSocialEnv(t)
	mine := e.claimHandle()
	ana := e.friendByRequest(mine)
	assert.Equal(t, []string{ana.handle}, handlesOf(e.get("/v1/social/friends"), "items"))

	assert.Equal(t, http.StatusNoContent, e.send(http.MethodPut, "/v1/social/blocks/"+ana.idString(), nil).Code)
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodPut, "/v1/social/blocks/"+ana.idString(), nil).Code)
	assert.Empty(t, handlesOf(e.get("/v1/social/friends"), "items"))
	assert.Equal(t, []string{ana.handle}, handlesOf(e.get("/v1/social/blocks"), "items"))

	// Both directions look exactly like nobody being there.
	fromAna := e.send(http.MethodGet, "/v1/social/users/"+mine, nil, ana.token)
	unknown := e.send(http.MethodGet, "/v1/social/users/nobody_has_this", nil, ana.token)
	assert.Equal(t, http.StatusNotFound, fromAna.Code)
	assert.Equal(t, unknown.Body.String(), fromAna.Body.String())
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/social/users/"+ana.handle, nil).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": mine}, ana.token).Code)

	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/social/blocks/"+ana.idString(), nil).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodDelete, "/v1/social/blocks/"+ana.idString(), nil).Code)
	assert.Equal(t, "none", relationshipOf(t, e.send(http.MethodGet, "/v1/social/users/"+ana.handle, nil)))

	assert.Equal(t, http.StatusUnprocessableEntity, e.send(http.MethodPut, "/v1/social/blocks/"+e.user.String(), nil).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPut, "/v1/social/blocks/"+uuid.NewString(), nil).Code)
	malformed := e.send(http.MethodDelete, "/v1/social/blocks/nope", nil)
	assert.Equal(t, "No one has that handle.", decode[map[string]any](t, malformed)["message"])
}

func TestReportsForRealUsersOnlyAndAccountDeleteRemovesTheGraph(t *testing.T) {
	e := newSocialEnv(t)
	mine := e.claimHandle()
	ana := e.friendlyUser()
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodPost, "/v1/social/reports", map[string]any{"userId": ana.idString(), "reason": "spam"}).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPost, "/v1/social/reports", map[string]any{"userId": uuid.NewString(), "reason": "spam"}).Code)
	long := e.send(http.MethodPost, "/v1/social/reports", map[string]any{"userId": ana.idString(), "reason": "other", "note": strings.Repeat("a", 1001)})
	assert.Equal(t, http.StatusUnprocessableEntity, long.Code)

	e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": mine}, ana.token)
	e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": ana.handle})
	assert.Equal(t, []string{ana.handle}, handlesOf(e.get("/v1/social/friends"), "items"))
	// The account export carries the social graph too.
	assert.Equal(t, []string{ana.handle}, handlesOf(e.get("/v1/me/export"), "friends"))
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/me", nil, ana.token).Code)
	assert.Empty(t, handlesOf(e.get("/v1/social/friends"), "items"))
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/social/users/"+ana.handle, nil).Code)
}

func TestLookupsAndRequestsAreLimitedPerHourSeparately(t *testing.T) {
	e := newSocialEnv(t)
	e.claimHandle()
	ana := e.friendlyUser()
	for range social.LookupsPerHour {
		require.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/social/users/"+freshHandle(), nil).Code)
	}
	over := e.send(http.MethodGet, "/v1/social/users/"+ana.handle, nil)
	assert.Equal(t, http.StatusTooManyRequests, over.Code)
	assert.Equal(t, "rate_limited", decode[map[string]any](t, over)["code"])
	// A spent lookup budget leaves requests alone.
	assert.Equal(t, http.StatusOK, e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": ana.handle}).Code)
	for range social.RequestsPerHour - 1 {
		e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": freshHandle()})
	}
	assert.Equal(t, http.StatusTooManyRequests, e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": ana.handle}).Code)
	// Another user is unaffected.
	assert.Equal(t, http.StatusOK, e.send(http.MethodGet, "/v1/social/users/"+ana.handle, nil, ana.token).Code)
}

func TestAFriendOrYourselfCostsNoLookup(t *testing.T) {
	e := newSocialEnv(t)
	mine := e.claimHandle()
	ana := e.friendByRequest(mine)
	for range social.RequestsPerHour - 1 {
		e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": freshHandle()})
	}
	assert.Equal(t, http.StatusTooManyRequests, e.send(http.MethodPost, "/v1/social/friend-requests", map[string]any{"handle": freshHandle()}).Code)
	// A spent request budget leaves lookups alone.
	bob := e.friendlyUser()
	assert.Equal(t, http.StatusOK, e.send(http.MethodGet, "/v1/social/users/"+bob.handle, nil).Code)
	for range social.LookupsPerHour - 1 {
		e.send(http.MethodGet, "/v1/social/users/"+freshHandle(), nil)
	}
	assert.Equal(t, http.StatusTooManyRequests, e.send(http.MethodGet, "/v1/social/users/"+freshHandle(), nil).Code)
	assert.Equal(t, http.StatusTooManyRequests, e.send(http.MethodGet, "/v1/social/users/"+bob.handle, nil).Code)
	// Profiles of friends open through this lookup on every hover: those, and yourself, are free.
	friend := e.send(http.MethodGet, "/v1/social/users/"+ana.handle, nil)
	assert.Equal(t, http.StatusOK, friend.Code)
	assert.Equal(t, "friend", relationshipOf(t, friend))
	assert.Equal(t, http.StatusOK, e.send(http.MethodGet, "/v1/social/users/"+mine, nil).Code)
}

func TestHandleChangesAreLimitedAndResavingIsFree(t *testing.T) {
	e := newSocialEnv(t)
	taken := e.friendlyUser().handle
	for range social.HandleChangesPerHour {
		require.Equal(t, http.StatusOK, e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": freshHandle()}).Code)
	}
	// "That handle is taken" would say who is on Aaru, so a taken one costs like any change.
	assert.Equal(t, http.StatusTooManyRequests, e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": taken}).Code)
	current := e.get("/v1/me")["handle"].(string)
	assert.Equal(t, http.StatusOK, e.send(http.MethodPut, "/v1/me/profile", map[string]any{"handle": current, "displayName": "Ana"}).Code)
}
